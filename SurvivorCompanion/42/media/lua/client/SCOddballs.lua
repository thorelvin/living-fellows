-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC.Oddballs = SC.Oddballs or {}

local Oddballs = SC.Oddballs
local VERSION = 1
local SCAN_INTERVAL_MS = 30000
local SAMPLE_BUDGET = 96
local MIN_DISTANCE = 35
local MAX_DISTANCE = 90
local MAX_UNRESOLVED = 2
local GOLDEN_ANGLE = 2.399963229728653
local SEARCH_OFFSETS = {
    { 0, 0 }, { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 },
    { 6, 6 }, { 6, -6 }, { -6, 6 }, { -6, -6 },
    { 12, 0 }, { -12, 0 }, { 0, 12 }, { 0, -12 },
}

local definitions = {
    { id = "gut_cloaked_red", name = "Red Odell Pruitt",
        archetype = "oddball_roamer", kind = "roamer",
        identity = { forename = "Red", surname = "Pruitt", gender = "male",
            outfit = "Young", extras = { "Base.Hat_BandanaMask" },
            gore = 1, dirt = 0.25, visualSeed = 3100141 }, module = "OddballRed" },
    { id = "window_spiffo_kevin", name = "Kevin Dupree",
        archetype = "oddball_resident", kind = "resident",
        identity = { forename = "Kevin", surname = "Dupree", gender = "male",
            outfit = "Spiffo", extras = { "Base.Hat_Spiffo", "Base.SpiffoTail" },
            visualSeed = 3100142 }, module = "OddballSpiffo" },
    { id = "shotgun_farmer_wendell", name = "Wendell Skaggs",
        archetype = "oddball_resident", kind = "resident",
        identity = { forename = "Wendell", surname = "Skaggs", gender = "male",
            outfit = "Farmer", extras = { "Base.Hat_StrawHat" },
            visualSeed = 3100143 }, module = "OddballWendell" },
    { id = "loretta_ten_and_two", name = "Loretta Biddle",
        archetype = "oddball_resident", kind = "vehicle_resident",
        recruitment = true, trade = true, firstEligibleOffsetDays = 4,
        identity = { forename = "Loretta", surname = "Biddle",
            gender = "female", outfit = "Teacher",
            extras = { "Base.Glasses_Reading" }, dirt = 0.5,
            visualSeed = 3100224 },
        kit = { items = { "Base.Clipboard", "Base.Pencil" } },
        module = "OddballLoretta" },
    { id = "milli_tea_and_trouble", name = "Milli Wilson",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, trade = true, firstEligibleOffsetDays = 3,
        identity = { forename = "Milli", surname = "Wilson",
            gender = "female", outfit = "Retiree",
            extras = { "Base.Jumper_DiamondPatternTINT",
                "Base.Trousers_WhiteTINT", "Base.Shoes_Slippers" },
            dirt = 0.1, visualSeed = 3100225 },
        module = "OddballMilli" },
    { id = "grocery_gale_mercer", name = "Gale Mercer",
        archetype = "oddball_psycho", kind = "resident",
        trade = true, recruitment = false, firstEligibleOffsetDays = 3,
        identity = { forename = "Gale", surname = "Mercer", gender = "male",
            outfit = "GigaMart_Employee", visualSeed = 3100156 },
        module = "OddballGale" },
    { id = "butcher_ambrose_kittredge", name = "Ambrose Kittredge",
        archetype = "oddball_psycho", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 3,
        identity = { forename = "Ambrose", surname = "Kittredge",
            gender = "male", outfit = "Meat_Master", gore = 0.5,
            visualSeed = 3100157 }, module = "OddballButch" },
    { id = "gunshop_cecil_haskins", name = "Cecil Ray Haskins",
        archetype = "oddball_psycho", kind = "resident",
        trade = true, recruitment = false, firstEligibleOffsetDays = 3,
        identity = { forename = "Cecil Ray", surname = "Haskins",
            gender = "male", outfit = "Hunter", visualSeed = 3100158 },
        module = "OddballCecil" },
    { id = "checkpoint_deputy_rhonda", name = "Deputy Rhonda Vance",
        archetype = "oddball_psycho", kind = "resident", captives = true,
        recruitment = true, firstEligibleOffsetDays = 3,
        identity = { forename = "Rhonda", surname = "Vance", gender = "female",
            outfit = "Sheriff_Deputy", visualSeed = 3100144 },
        module = "OddballDeputy" },
    { id = "cult_brother_silas", name = "Brother Silas Crane",
        archetype = "oddball_psycho", kind = "resident",
        firstEligibleOffsetDays = 3, memberCountMin = 3, memberCountMax = 4,
        recruitment = false,
        identity = { forename = "Silas", surname = "Crane", gender = "male",
            outfit = "Priest", visualSeed = 3100145 },
        memberIdentities = {
            { forename = "Silas", surname = "Crane", gender = "male",
                outfit = "Priest", visualSeed = 3100145 },
            { forename = "Ada", surname = "Flint", gender = "female",
                outfit = "Cultist", visualSeed = 3100146 },
            { forename = "Jonah", surname = "Vale", gender = "male",
                outfit = "Cultist", visualSeed = 3100147 },
            { forename = "Morris", surname = "Pike", gender = "male",
                outfit = "Cultist", visualSeed = 3100148 },
        }, memberRoles = { "leader", "cultist", "cultist", "cultist" },
        module = "OddballSilas" },
    { id = "ringmaster_rusty_pell", name = "Rusty Pell",
        archetype = "oddball_psycho", kind = "resident",
        firstEligibleOffsetDays = 3, recruitment = true,
        identity = { forename = "Rusty", surname = "Pell", gender = "male",
            outfit = "CostumeWildWestClown", visualSeed = 3100149 },
        module = "OddballRusty" },
    { id = "wedding_lonnie_tackett", name = "Lonnie Tackett",
        archetype = "oddball_psycho", kind = "resident", recruitment = false,
        firstEligibleOffsetDays = 3,
        identity = { forename = "Lonnie", surname = "Tackett", gender = "male",
            outfit = "Groom", visualSeed = 3100150 },
        module = "OddballLonnie" },
    { id = "postman_virgil_toombs", name = "Virgil Toombs",
        archetype = "oddball_resident", kind = "resident", recruitment = true,
        identity = { forename = "Virgil", surname = "Toombs", gender = "male",
            outfit = "Postal", visualSeed = 3100151 },
        module = "OddballVirgil" },
    { id = "duelist_clem_sutter", name = "Clem Sutter",
        archetype = "oddball_resident", kind = "resident", recruitment = true,
        identity = { forename = "Clem", surname = "Sutter", gender = "male",
            outfit = "MallSecurity", extras = { "Base.Hat_Cowboy" },
            visualSeed = 3100152 }, module = "OddballClem" },
    { id = "sniper_purdy_clan", name = "The Purdy Clan",
        archetype = "oddball_psycho", kind = "resident",
        firstEligibleOffsetDays = 3, memberCountMin = 3, memberCountMax = 3,
        trade = true, recruitment = false,
        identity = { forename = "Harlan", surname = "Purdy", gender = "male",
            outfit = "Hunter", visualSeed = 3100153 },
        memberIdentities = {
            { forename = "Harlan", surname = "Purdy", gender = "male",
                outfit = "Hunter", visualSeed = 3100153 },
            { forename = "Ellis", surname = "Purdy", gender = "male",
                outfit = "Redneck", visualSeed = 3100154 },
            { forename = "Wade", surname = "Purdy", gender = "male",
                outfit = "Redneck", visualSeed = 3100155 },
        }, memberRoles = { "leader", "son", "son" },
        module = "OddballPurdy" },
    { id = "duchess_hollis_burkett", name = "Hollis Burkett",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 3,
        identity = { forename = "Hollis", surname = "Burkett",
            gender = "male", outfit = "Farmer", visualSeed = 3100159 },
        module = "OddballHollis" },
    { id = "party_room12_delbert", name = "Delbert Sloan",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 3,
        identity = { forename = "Delbert", surname = "Sloan",
            gender = "male", outfit = "Bathrobe",
            extras = { "Base.Hat_PartyHat_TINT" },
            visualSeed = 3100160 }, module = "OddballRoom12" },
    { id = "ranger_june_whitlock", name = "Ranger June Whitlock",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 3,
        identity = { forename = "June", surname = "Whitlock",
            gender = "female", outfit = "Ranger", visualSeed = 3100161 },
        module = "OddballJune" },
    { id = "knox_defense_league", name = "Knox Defense League",
        archetype = "oddball_psycho", kind = "patrol",
        memberCountMin = 4, memberCountMax = 4,
        recruitment = false, firstEligibleOffsetDays = 12,
        identity = { forename = "Orson", surname = "Keene", gender = "male",
            outfit = "PrivateMilitia", visualSeed = 3100162 },
        memberIdentities = {
            { forename = "Orson", surname = "Keene", gender = "male",
                outfit = "PrivateMilitia", visualSeed = 3100162 },
            { forename = "Buck", surname = "Ramey", gender = "male",
                outfit = "PrivateMilitia", visualSeed = 3100163 },
            { forename = "Mara", surname = "Graves", gender = "female",
                outfit = "PrivateMilitia", visualSeed = 3100164 },
            { forename = "Eldon", surname = "Price", gender = "male",
                outfit = "PrivateMilitia", visualSeed = 3100165 },
        }, memberRoles = { "leader", "inspector", "rifleman", "rifleman" },
        module = "OddballDefenseLeague" },
    { id = "doctor_vernon_ashby", name = "Dr. Vernon Ashby",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 9,
        identity = { forename = "Vernon", surname = "Ashby", gender = "male",
            outfit = "MadScientist", visualSeed = 3100166 },
        module = "OddballAshby" },
    { id = "sin_gluttony_bonnie", name = "Bonnie Mae Leach",
        archetype = "oddball_psycho", kind = "resident", trade = true,
        recruitment = false, firstEligibleOffsetDays = 5,
        identity = { forename = "Bonnie Mae", surname = "Leach",
            gender = "female", outfit = "Waiter_PizzaWhirled",
            visualSeed = 3100167 }, module = "OddballSins" },
    { id = "sin_greed_lyman", name = "Lyman Spurlock",
        archetype = "oddball_resident", kind = "resident", trade = true,
        recruitment = false, firstEligibleOffsetDays = 5,
        identity = { forename = "Lyman", surname = "Spurlock",
            gender = "male", outfit = "Classy", visualSeed = 3100168 },
        module = "OddballSins" },
    { id = "sin_sloth_harlan", name = "Harlan Goode",
        archetype = "oddball_resident", kind = "resident", trade = true,
        recruitment = false, firstEligibleOffsetDays = 5,
        identity = { forename = "Harlan", surname = "Goode",
            gender = "male", outfit = "Bathrobe", visualSeed = 3100169 },
        module = "OddballSins" },
    { id = "sin_wrath_duane", name = "Duane Sykes",
        archetype = "oddball_psycho", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 5,
        identity = { forename = "Duane", surname = "Sykes",
            gender = "male", outfit = "BoxingRed", visualSeed = 3100170 },
        module = "OddballSins" },
    { id = "sin_pride_darlene", name = "Darlene Vickers",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 5,
        identity = { forename = "Darlene", surname = "Vickers",
            gender = "female", outfit = "Classy", visualSeed = 3100171 },
        module = "OddballSins" },
    { id = "christmas_kris_kimbrough", name = "Kris Kimbrough",
        archetype = "oddball_psycho", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 6,
        identity = { forename = "Kris", surname = "Kimbrough",
            gender = "male", outfit = "Santa", visualSeed = 3100172 },
        module = "OddballKris" },
    { id = "peddler_mister_ebb", name = "Mister Ebb",
        archetype = "oddball_roamer", kind = "roamer", trade = true,
        recruitment = false, firstEligibleOffsetDays = 5,
        identity = { forename = "Mister", surname = "Ebb", gender = "male",
            outfit = "Trader", extras = { "Base.Hat_GasMask" },
            visualSeed = 3100173 }, module = "OddballEbb" },
    { id = "dewey_prentice_hollowell", name = "Prentice Hollowell",
        archetype = "oddball_roamer", kind = "roamer",
        recruitment = true, firstEligibleOffsetDays = 6,
        identity = { forename = "Prentice", surname = "Hollowell",
            gender = "male", outfit = "Classy",
            extras = { "Base.Hat_Fedora" }, visualSeed = 3100174 },
        module = "OddballPrentice" },
    { id = "watcher_pettigrew_lusk", name = "Pettigrew Lusk",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 8,
        identity = { forename = "Pettigrew", surname = "Lusk",
            gender = "male", outfit = "OfficeWorker",
            extras = { "Base.Hat_TinFoilHat" }, visualSeed = 3100175 },
        module = "OddballLusk" },
    { id = "seer_aunt_velma_crisp", name = "Aunt Velma Crisp",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 7,
        identity = { forename = "Velma", surname = "Crisp",
            gender = "female", outfit = "Gaudy", visualSeed = 3100176 },
        module = "OddballVelma" },
    { id = "fan_corey_biggs", name = "Corey Biggs",
        archetype = "oddball_roamer", kind = "witness",
        recruitment = true, firstEligibleOffsetDays = 0,
        identity = { forename = "Corey", surname = "Biggs",
            gender = "male", outfit = "Student", visualSeed = 3100177 },
        module = "OddballCorey" },
    { id = "knight_sir_dwight", name = "Sir Dwight of Muldraugh",
        archetype = "oddball_roamer", kind = "knight",
        recruitment = true, firstEligibleOffsetDays = 8,
        identity = { forename = "Dwight", surname = "Muldraugh",
            gender = "male", outfit = "ArmorTest_Metal",
            visualSeed = 3100178 }, module = "OddballDwight" },
    { id = "trickster_lucky_royce", name = "Lucky Royce Pickett",
        archetype = "oddball_roamer", kind = "trickster",
        recruitment = true, firstEligibleOffsetDays = 9,
        identity = { forename = "Royce", surname = "Pickett",
            gender = "male", outfit = "Thug", visualSeed = 3100179 },
        module = "OddballRoyce" },
    { id = "sniper_old_mose_calloway", name = "Old Mose Calloway",
        archetype = "oddball_psycho", kind = "mose",
        recruitment = false, firstEligibleOffsetDays = 10,
        identity = { forename = "Mose", surname = "Calloway",
            gender = "male", outfit = "Ghillie", visualSeed = 3100180 },
        module = "OddballMose" },
    { id = "preacher_reverend_amos", name = "Reverend Amos Teague",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, trade = true,
        firstEligibleOffsetDays = 10,
        identity = { forename = "Amos", surname = "Teague",
            gender = "male", outfit = "Priest", visualSeed = 3100181 },
        module = "OddballAmos" },
    { id = "slot_lester_voss", name = "Lester Voss",
        archetype = "oddball_resident", kind = "resident",
        trade = true, recruitment = false, memberCountMin = 2,
        memberCountMax = 2, firstEligibleOffsetDays = 10,
        identity = { forename = "Lester", surname = "Voss", gender = "male",
            outfit = "Bathrobe", visualSeed = 3100182 },
        memberIdentities = {
            { forename = "Lester", surname = "Voss", gender = "male",
                outfit = "Bathrobe", visualSeed = 3100182 },
            { forename = "Martha", surname = "Voss", gender = "female",
                outfit = "OfficeWorker", visualSeed = 3100183 },
        }, memberRoles = { "husband", "trader" },
        module = "OddballLester" },
    { id = "silver_visitors_fellowship", name = "Fellowship of the Silver Visitors",
        archetype = "oddball_resident", kind = "visitors",
        memberCountMin = 3, memberCountMax = 4,
        recruitment = false, firstEligibleOffsetDays = 11,
        identity = { forename = "Elias", surname = "Sutton", gender = "male",
            outfit = "Generic01", extras = { "Base.Hat_TinFoilHat" },
            visualSeed = 3100184 },
        memberIdentities = {
            { forename = "Elias", surname = "Sutton", gender = "male",
                outfit = "Generic01", extras = { "Base.Hat_TinFoilHat" },
                visualSeed = 3100184 },
            { forename = "Nora", surname = "Bell", gender = "female",
                outfit = "Generic03", extras = { "Base.Hat_TinFoilHat" },
                visualSeed = 3100185 },
            { forename = "Caleb", surname = "Sutton", gender = "male",
                outfit = "Generic04", extras = { "Base.Hat_TinFoilHat" },
                visualSeed = 3100186 },
            { forename = "June", surname = "Bell", gender = "female",
                outfit = "Generic05", extras = { "Base.Hat_TinFoilHat" },
                visualSeed = 3100187 },
        }, memberRoles = { "leader", "believer", "believer", "believer" },
        module = "OddballVisitors" },
    { id = "tupelo_boys", name = "The Tupelo Boys",
        archetype = "oddball_resident", kind = "resident",
        memberCountMin = 3, memberCountMax = 4,
        recruitment = true, firstEligibleOffsetDays = 11,
        identity = { forename = "Ray Lee", surname = "Toller", gender = "male",
            outfit = "Gaudy", extras = { "Base.Glasses_Aviators" },
            visualSeed = 3100188 },
        memberIdentities = {
            { forename = "Ray Lee", surname = "Toller", gender = "male",
                outfit = "Gaudy", extras = { "Base.Glasses_Aviators" },
                visualSeed = 3100188 },
            { forename = "Jerry", surname = "Blue", gender = "male",
                outfit = "Rocker", extras = { "Base.Glasses_Aviators" },
                visualSeed = 3100189 },
            { forename = "Otis", surname = "King", gender = "male",
                outfit = "Gaudy", extras = { "Base.Glasses_Aviators" },
                visualSeed = 3100190 },
            { forename = "Hank", surname = "Lee", gender = "male",
                outfit = "Rocker", extras = { "Base.Glasses_Aviators" },
                visualSeed = 3100191 },
        }, memberRoles = { "leader", "guard", "musician", "guard" },
        module = "OddballTupelo" },
    { id = "rosewood_auxiliary", name = "Rosewood Baptist Ladies' Auxiliary",
        archetype = "oddball_resident", kind = "resident",
        memberCountMin = 3, memberCountMax = 3,
        trade = true, recruitment = true,
        firstEligibleOffsetDays = 11,
        identity = { forename = "Dorothy", surname = "Raines",
            gender = "female", outfit = "Retiree", visualSeed = 3100192 },
        memberIdentities = {
            { forename = "Dorothy", surname = "Raines", gender = "female",
                outfit = "Retiree", visualSeed = 3100192 },
            { forename = "Evelyn", surname = "Price", gender = "female",
                outfit = "Retiree", visualSeed = 3100193 },
            { forename = "Opal", surname = "Mercer", gender = "female",
                outfit = "Retiree", visualSeed = 3100194 },
        }, memberRoles = { "leader", "baker", "quiet_baker" },
        module = "OddballAuxiliary" },
    { id = "doctor_pest", name = "Doctor Pest",
        archetype = "oddball_resident", kind = "rival_pair",
        recruitment = true, firstEligibleOffsetDays = 12,
        identity = { forename = "Doctor", surname = "Pest", gender = "male",
            outfit = "ExterminatorSuited", visualSeed = 3100195 },
        module = "OddballRivals" },
    { id = "bluegrass_bolt", name = "The Bluegrass Bolt",
        archetype = "oddball_resident", kind = "paired_only",
        recruitment = true, firstEligibleOffsetDays = 12,
        identity = { forename = "Bluegrass", surname = "Bolt",
            gender = "male", outfit = "CostumeUppermostFirearm",
            extras = { "Base.Glasses_Aviators" },
            visualSeed = 3100196 }, module = "OddballRivals" },
    { id = "bledsoe_brothers_still", name = "The Bledsoe Brothers",
        archetype = "oddball_resident", kind = "resident",
        memberCountMin = 2, memberCountMax = 2,
        trade = true, recruitment = false,
        firstEligibleOffsetDays = 12,
        identity = { forename = "Coy", surname = "Bledsoe",
            gender = "male", outfit = "Redneck", visualSeed = 3100197 },
        memberIdentities = {
            { forename = "Coy", surname = "Bledsoe", gender = "male",
                outfit = "Redneck", visualSeed = 3100197 },
            { forename = "Dale", surname = "Bledsoe", gender = "male",
                outfit = "Farmer", visualSeed = 3100198 },
        }, memberRoles = { "distiller", "guard" },
        module = "OddballBledsoe" },
    { id = "werewolf_dalton_reese", name = "Dalton Reese",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 12,
        identity = { forename = "Dalton", surname = "Reese",
            gender = "male", outfit = "Hunter", visualSeed = 3100199 },
        module = "OddballWerewolf" },
    { id = "cameraman_skeeter_bowles", name = "Skeeter Bowles",
        archetype = "oddball_roamer", kind = "challenge",
        recruitment = false, firstEligibleOffsetDays = 8,
        identity = { forename = "Skeeter", surname = "Bowles",
            gender = "male", outfit = "Tourist", visualSeed = 3100200 },
        module = "OddballSkeeter" },
    { id = "digger_merle_lusby", name = "Digger Merle Lusby",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 9,
        identity = { forename = "Merle", surname = "Lusby",
            gender = "male", outfit = "Hobbo", visualSeed = 3100201 },
        module = "OddballMerle" },
    { id = "crabtree_sheep_farm", name = "The Crabtree Sheep Farm",
        archetype = "oddball_resident", kind = "resident",
        memberCountMin = 2, memberCountMax = 2,
        recruitment = true, trade = true, firstEligibleOffsetDays = 10,
        identity = { forename = "Lyle", surname = "Crabtree",
            gender = "male", outfit = "Bathrobe", visualSeed = 3100202 },
        memberIdentities = {
            { forename = "Lyle", surname = "Crabtree", gender = "male",
                outfit = "Bathrobe", visualSeed = 3100202 },
            { forename = "Dewayne", surname = "Crabtree", gender = "male",
                outfit = "Farmer", visualSeed = 3100203 },
        }, memberRoles = { "owner", "shepherd" },
        module = "OddballCrabtree" },
    { id = "jedediah_cattle_drive", name = "Jedediah Cole",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, trade = true, firstEligibleOffsetDays = 10,
        identity = { forename = "Jedediah", surname = "Cole",
            gender = "male", outfit = "CostumeWildWestCowpoke",
            visualSeed = 3100204 }, module = "OddballJedediah" },
    { id = "gideon_mister_buttons", name = "Gideon and Mister Buttons",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 10,
        identity = { forename = "Gideon", surname = "Pike",
            gender = "male", outfit = "Generic03",
            extras = { "Base.Hat_TinFoilHat" },
            visualSeed = 3100205 }, module = "OddballGideon" },
    { id = "renfro_rat_king", name = "Renfro, the Rat King",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, trade = true, firstEligibleOffsetDays = 12,
        identity = { forename = "Renfro", surname = "Vail",
            gender = "male", outfit = "Hobbo", visualSeed = 3100206 },
        module = "OddballRenfro" },
    { id = "trestle_goatman", name = "The Trestle Goatman",
        archetype = "oddball_psycho", kind = "resident",
        recruitment = false, trade = true,
        firstEligibleOffsetDays = 14,
        identity = { forename = "Trestle", surname = "Goatman",
            gender = "male", outfit = "ArmorTest_Bone",
            visualSeed = 3100207 }, module = "OddballGoatman" },
    { id = "tolliver_farm_siege", name = "The Tolliver Farm Siege",
        archetype = "oddball_resident", kind = "resident",
        memberCountMin = 4, memberCountMax = 4,
        recruitment = false, firstEligibleOffsetDays = 14,
        identity = { forename = "Earl", surname = "Tolliver",
            gender = "male", outfit = "Farmer", visualSeed = 3100208 },
        memberIdentities = {
            { forename = "Earl", surname = "Tolliver", gender = "male",
                outfit = "Farmer", visualSeed = 3100208 },
            { forename = "Maybelle", surname = "Tolliver", gender = "female",
                outfit = "Farmer", visualSeed = 3100209 },
            { forename = "Junior", surname = "Tolliver", gender = "male",
                outfit = "Redneck", visualSeed = 3100210 },
            { forename = "Nora", surname = "Tolliver", gender = "female",
                outfit = "Redneck", visualSeed = 3100211 },
        }, memberRoles = { "leader", "watcher", "watcher", "watcher" },
        module = "OddballTolliver" },
    { id = "sleeping_it_off", name = "Sleeping It Off",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 7,
        identity = { forename = "Darla Jo", surname = "Simms",
            gender = "female", outfit = "StripperPink",
            visualSeed = 3100212 }, module = "OddballSleeper" },
    { id = "man_in_the_chair", name = "Elmer Gaskins",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 13,
        identity = { forename = "Elmer", surname = "Gaskins",
            gender = "male", outfit = "OfficeWorker", gore = 0.3,
            dirt = 0.7, visualSeed = 3100214 }, module = "OddballElmer" },
    { id = "big_chris_rascal", name = "Big Chris and Rascal",
        archetype = "oddball_roamer", kind = "trash_runner",
        recruitment = true, trade = true, firstEligibleOffsetDays = 8,
        identity = { forename = "Chris", surname = "Puckett",
            gender = "male", outfit = "Woodcut",
            extras = { "Base.Hat_Raccoon" }, dirt = 0.9,
            visualSeed = 3100215 }, module = "OddballBigChris" },
    { id = "tommy_two_lengths", name = "Tommy Two Lengths Beaumont",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 10,
        identity = { forename = "Tommy", surname = "Beaumont",
            gender = "male", outfit = "Jockey03",
            visualSeed = 3100216 }, module = "OddballTommy" },
    { id = "gordon_pettibone", name = "Gordon Pettibone",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, trade = true, firstEligibleOffsetDays = 12,
        identity = { forename = "Gordon", surname = "Pettibone",
            gender = "male", outfit = "HazardSuit",
            extras = { "Base.Hat_GasMask" }, visualSeed = 3100217 },
        module = "OddballGordon" },
    { id = "morton_buster", name = "Morton Feeney and Buster",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 12,
        identity = { forename = "Morton", surname = "Feeney",
            gender = "male", outfit = "Classy",
            extras = { "Base.Tie_BowTieFull" }, visualSeed = 3100218 },
        module = "OddballMorton" },
    { id = "mien_ward", name = "Mien Ward",
        archetype = "oddball_roamer", kind = "resident",
        recruitment = true, trade = true, firstEligibleOffsetDays = 8,
        identity = { forename = "Mien", surname = "Ward", gender = "male",
            extras = { "Base.Tshirt_Metal", "Base.Jacket_Black",
                "Base.Trousers_Black", "Base.Shoes_BlackBoots",
                "Base.Necklace_Choker" }, visualSeed = 3100219 },
        module = "OddballMien" },
    { id = "grinder_berg", name = "Grinder Berg",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, trade = true, firstEligibleOffsetDays = 10,
        identity = { forename = "Grinder", surname = "Berg",
            gender = "male", outfit = "ConstructionWorker",
            extras = { "Base.Hat_HardHat", "Base.Glasses_SafetyGoggles" },
            keepsakeType = "Base.Screwdriver", visualSeed = 3100220 },
        module = "OddballGrinder" },
    { id = "survivalist_locked_horde", name = "Caleb Harker",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 5,
        identity = { forename = "Caleb", surname = "Harker",
            gender = "male", outfit = "Hunter",
            extras = { "Base.Hat_BonnieHat" }, dirt = 0.18,
            visualSeed = 3100221 },
        kit = { weapon = "Base.HuntingKnife",
            items = { "Base.Rope", "Base.Twine", "Base.Matchbox",
                "Base.Bandage", "Base.CannedSardines", "Base.TinOpener" } },
        module = "OddballSurvivalist" },
    { id = "voice_actor_vera_quill", name = "Vera Quill",
        archetype = "oddball_resident", kind = "resident",
        recruitment = false, firstEligibleOffsetDays = 4,
        identity = { forename = "Vera", surname = "Quill",
            gender = "female", outfit = "Classy",
            extras = { "Base.Glasses_Reading", "Base.Scarf_White" },
            dirt = 0.08, visualSeed = 3100222 },
        kit = { weapon = "Base.KitchenKnife", equipWeapon = false,
            items = { "Base.Notebook", "Base.Pencil", "Base.Hairspray2",
                "Base.MakeupEyeshadow", "Base.Mirror" } },
        module = "OddballVoiceActor" },
    { id = "pyromaniac_earl_kessler", name = "Earl Kessler",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 6,
        identity = { forename = "Earl", surname = "Kessler",
            gender = "male", outfit = "Rocker",
            extras = { "Base.Jacket_Leather", "Base.Glasses_Sun" },
            dirt = 0.35, visualSeed = 3100223 },
        kit = { weapon = "Base.PipeWrench",
            items = { "Base.Lighter", "Base.CigarettePack",
                "Base.Matchbox", "Base.Bandage" } },
        module = "OddballPyromaniac" },
    { id = "garage_rescue_eli_rourke", name = "Eli Rourke",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 4,
        identity = { forename = "Eli", surname = "Rourke",
            gender = "male", outfit = "Mechanic", dirt = 0.32,
            visualSeed = 3100226 },
        kit = { weapon = "Base.Wrench", equipWeapon = false,
            items = { "Base.Torch", "Base.Notebook", "Base.Pencil",
                "Base.CigarettePack" } },
        module = "OddballGarageRescue" },
    { id = "survivalist05_mid_storyteller", name = "Silas Reed",
        archetype = "oddball_resident", kind = "forest_camp",
        recruitment = true, firstEligibleOffsetDays = 3,
        identity = { forename = "Silas", surname = "Reed",
            gender = "male", outfit = "Survivalist05_Mid",
            dirt = 0.22, visualSeed = 3100228 },
        kit = { weapon = "Base.HuntingKnife",
            items = { "Base.FishingRod", "Base.FishingLine", "Base.Bobber",
                "Base.Worm", "Base.Tacklebox", "Base.Matchbox",
                "Base.WaterBottle", "Base.CannedSardines",
                "Base.TinOpener" } },
        module = "OddballCampStoryteller" },
    { id = "radio_rescue_nate_duvall", name = "Nate Duvall",
        archetype = "oddball_resident", kind = "resident",
        recruitment = true, firstEligibleOffsetDays = 4,
        identity = { forename = "Nate", surname = "Duvall",
            gender = "male", outfit = "ConstructionWorker", dirt = 0.4,
            visualSeed = 3100227 },
        kit = { items = { "Base.WaterBottle", "Base.Map",
            "Base.Pencil", "Base.Notebook", "Base.Torch" } },
        module = "OddballDehydrated" },
}
-- Scene modules own their signature weapons and reward stock. These small
-- personal kits fill the gaps without changing an encounter's combat script.
-- For a group, the kit belongs to its first named member only.
local supplementalKits = {
    window_spiffo_kevin = { items = { "Base.Spiffo", "Base.Bandage" } },
    shotgun_farmer_wendell = { items = { "Base.CannedCorn", "Base.TinOpener", "Base.WaterBottle" } },
    grocery_gale_mercer = { items = { "Base.Pen", "Base.Notebook", "Base.CigarettePack" } },
    butcher_ambrose_kittredge = { items = { "Base.Salt", "Base.Twine" } },
    checkpoint_deputy_rhonda = { items = { "Base.Torch", "Base.Whistle" } },
    cult_brother_silas = { items = { "Base.Book", "Base.Candle" } },
    ringmaster_rusty_pell = { items = { "Base.Dice", "Base.CardDeck" } },
    wedding_lonnie_tackett = { items = { "Base.Photo", "Base.Tissue" } },
    postman_virgil_toombs = { items = { "Base.Pen", "Base.Map" } },
    duelist_clem_sutter = { items = { "Base.Dice", "Base.Bandage" } },
    sniper_purdy_clan = { items = { "Base.CannedSardines", "Base.TinOpener" } },
    duchess_hollis_burkett = { items = { "Base.SeedBag", "Base.CigarettePack" } },
    doctor_vernon_ashby = { items = { "Base.Notebook", "Base.Pencil" } },
    sin_gluttony_bonnie = { items = { "Base.Salt", "Base.TinOpener" } },
    sin_greed_lyman = { items = { "Base.Wallet", "Base.MoneyBundle" } },
    sin_sloth_harlan = { items = { "Base.Pills", "Base.Tissue" } },
    sin_wrath_duane = { items = { "Base.Bandage", "Base.WaterBottle" } },
    sin_pride_darlene = { items = { "Base.Mirror", "Base.Hairspray2" } },
    christmas_kris_kimbrough = { items = { "Base.Card_Christmas", "Base.Charcoal" } },
    dewey_prentice_hollowell = { items = { "Base.Notebook", "Base.Pen", "Base.CigarettePack" } },
    watcher_pettigrew_lusk = { items = { "Base.Notebook", "Base.Pencil", "Base.Battery" } },
    seer_aunt_velma_crisp = { items = { "Base.Candle", "Base.Matches", "Base.Notebook" } },
    fan_corey_biggs = { items = { "Base.Pencil", "Base.Crisps" } },
    knight_sir_dwight = { items = { "Base.Bandage", "Base.WaterBottle" } },
    trickster_lucky_royce = { items = { "Base.Dice", "Base.CardDeck", "Base.PokerChips" } },
    sniper_old_mose_calloway = { items = { "Base.CannedSardines", "Base.TinOpener" } },
    preacher_reverend_amos = { items = { "Base.Book", "Base.Candle", "Base.Matches" } },
    silver_visitors_fellowship = { items = { "Base.Notebook", "Base.Pencil" } },
    doctor_pest = { items = { "Base.Bandage", "Base.Tissue" } },
    bluegrass_bolt = { items = { "Base.Whistle", "Base.Bandage" } },
    bledsoe_brothers_still = { items = { "Base.Matchbox", "Base.CigarettePack" } },
    werewolf_dalton_reese = { items = { "Base.Bandage", "Base.Mirror", "Base.Tissue" } },
    crabtree_sheep_farm = { items = { "Base.Twine", "Base.WaterBottle" } },
    jedediah_cattle_drive = { items = { "Base.Rope", "Base.Twine" } },
    gideon_mister_buttons = { items = { "Base.Screwdriver", "Base.Notebook" } },
    renfro_rat_king = { items = { "Base.Cheese", "Base.Twine" } },
    man_in_the_chair = { items = { "Base.Pills", "Base.CigarettePack", "Base.Tissue" } },
    tommy_two_lengths = { items = { "Base.Dice", "Base.CigarettePack" } },
    gordon_pettibone = { items = { "Base.TinOpener", "Base.Bandage" } },
    morton_buster = { items = { "Base.Pencil", "Base.SheetPaper2" } },
}
local byId = {}
for _, definition in ipairs(definitions) do
    if not definition.kit then definition.kit = supplementalKits[definition.id] end
    byId[definition.id] = definition
end

local function freshState()
    return { version = VERSION, lastSeedDay = nil,
        seeded = {}, retired = {}, pending = nil }
end

local state = freshState()
local nextScanAt = 0
local nextRecruitedPulseAt = 0
local scanSerial = 0

local function U() return SC.GameplayUtil end

local function roomGuard(method, ...)
    local owner = SC.OddballRoomGuard
    local callback = type(owner) == "table" and owner[method] or nil
    if type(callback) ~= "function" then return false, "room_guard_unavailable" end
    local called, result, reason = pcall(callback, ...)
    if not called and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("oddballs", nil,
            "encounter room guard failed", tostring(result))
    end
    return called and result ~= false, called and reason or tostring(result)
end

local function worldDay()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local hours, called = U().call(gameTime, "getWorldAgeHours")
            if called and tonumber(hours) then
                return math.floor(tonumber(hours) / 24)
            end
        end
    end
    return math.floor(U().nowMs() / 86400000)
end

local function worldClockHour()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    local clock = select(1, U().call(time, "getTimeOfDay"))
    return tonumber(clock)
end

local function point(square)
    local x, y, z = U().position(square)
    if x == nil then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
end

local function roomName(square)
    local room, roomCalled = U().call(square, "getRoom")
    if not roomCalled or room == nil then return nil end
    local name, called = U().call(room, "getName")
    return called and type(name) == "string" and string.lower(name) or nil
end

local function candidateUnseen(square, player, allowSeen)
    if square == nil or player == nil then return false end
    if not U().isSafeSpawnSquare(square) then return false end
    if allowSeen == true then return true end
    local index, called = U().call(player, "getPlayerNum")
    if not called or tonumber(index) == nil then return false end
    local seen, seenCalled = U().call(square, "isCanSee", math.floor(index))
    if not seenCalled or seen == true then return false end
    return not U().canSee(player, square)
end

local function objectTileUnseen(square, player, allowSeen)
    if square == nil or player == nil then return false end
    if allowSeen == true then return true end
    local index = select(1, U().call(player, "getPlayerNum"))
    if tonumber(index) == nil then return false end
    return select(1, U().call(square, "isCanSee",
        math.floor(index))) ~= true
        and U().canSee(player, square) ~= true
end

local function moduleFor(group)
    local story = type(group) == "table" and group.oddball or nil
    local definition = story and byId[story.id] or nil
    return definition and SC[definition.module] or nil
end

local function callModule(group, methodName, ...)
    local module = moduleFor(group)
    if type(module) ~= "table" or type(module[methodName]) ~= "function" then
        return nil, "oddball_behavior_unavailable"
    end
    local called, value, reason = pcall(module[methodName], ...)
    if not called then
        if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("oddballs", group and group.id,
                "character behavior failed", tostring(value))
        end
        return nil, "oddball_behavior_failed"
    end
    return value, reason
end

local function isResidentRoom(id, name)
    if type(name) ~= "string" then return false end
    if id == "window_spiffo_kevin" then
        return string.find(name, "spiff", 1, true) ~= nil
            or string.find(name, "clothingstore", 1, true) ~= nil
    end
    if id == "shotgun_farmer_wendell" or id == "duchess_hollis_burkett"
        or id == "crabtree_sheep_farm"
        or id == "jedediah_cattle_drive" then
        return string.find(name, "barn", 1, true) ~= nil
            or string.find(name, "farmstorage", 1, true) ~= nil
    end
    if id == "grocery_gale_mercer" then
        return name == "grocery" or name == "gigamart"
    end
    if id == "butcher_ambrose_kittredge" then return name == "butcher" end
    if id == "gunshop_cecil_haskins" then return name == "gunstore" end
    if id == "checkpoint_deputy_rhonda" then
        return name == "policestorage" or name == "policelocker"
    end
    if id == "cult_brother_silas" or id == "wedding_lonnie_tackett"
        or id == "digger_merle_lusby"
        or id == "preacher_reverend_amos" then
        return name == "church"
    end
    if id == "ringmaster_rusty_pell" then
        return name == "theatre" or name == "theater"
    end
    if id == "postman_virgil_toombs" then
        return name == "post" or name == "postoffice"
    end
    if id == "duelist_clem_sutter" then
        return name == "clothingstore" or name == "bar"
    end
    if id == "sniper_purdy_clan" then
        return name == "barn" or name == "farmstorage"
    end
    if id == "party_room12_delbert" then
        return name == "motelroom" or name == "bedroom"
    end
    if id == "ranger_june_whitlock" then
        return name == "hunting" or name == "hunterstorage"
            or name == "rangeroffice" or name == "rangerhall"
    end
    if id == "doctor_vernon_ashby" then
        return name == "laboratory" or name == "medical"
            or name == "classroom" or name == "medicalstorage"
    end
    if id == "sin_gluttony_bonnie" then
        return name == "pizzawhirled" or name == "bakery"
    end
    if id == "sin_greed_lyman" then return name == "pawnshop" end
    if id == "sin_sloth_harlan" then
        return name == "livingroom" or name == "lounge"
    end
    if id == "sin_wrath_duane" then return name == "gym" end
    if id == "sin_pride_darlene" then
        return name == "theatre" or name == "theater"
    end
    if id == "christmas_kris_kimbrough" then return name == "toystore" end
    if id == "watcher_pettigrew_lusk" then
        return name == "livingroom" or name == "bedroom"
    end
    if id == "seer_aunt_velma_crisp" then
        return name == "motelroom" or name == "bedroom"
    end
    if id == "slot_lester_voss" then return name == "bedroom" end
    if id == "tupelo_boys" then return name == "bar" end
    if id == "rosewood_auxiliary" then return name == "kitchen" end
    if id == "doctor_pest" then
        return name == "medical" or name == "office"
            or name == "classroom"
    end
    if id == "bledsoe_brothers_still" then
        return name == "shed" or name == "farmstorage"
    end
    if id == "werewolf_dalton_reese" then return name == "bedroom" end
    if id == "gideon_mister_buttons" then return name == "kitchen" end
    if id == "renfro_rat_king" then
        return name == "basement" or name == "cellar"
            or name == "storage" or name == "utility"
    end
    if id == "trestle_goatman" then
        return name == "shed" or name == "farmstorage"
    end
    if id == "tolliver_farm_siege" then
        return name == "livingroom" or name == "kitchen"
    end
    if id == "sleeping_it_off" then
        return name == "bedroom" or name == "motelroom"
    end
    if id == "man_in_the_chair" then return name == "livingroom" end
    if id == "tommy_two_lengths" then
        return name == "barn" or name == "farmstorage"
    end
    if id == "gordon_pettibone" then
        return name == "livingroom" or name == "kitchen"
    end
    if id == "morton_buster" then
        return name == "theatre" or name == "theater" or name == "bar"
    end
    if id == "mien_ward" then
        return name == "grocery" or name == "cornerstore"
            or name == "liquorstore" or name == "brewery"
            or name == "whiskeybottling" or name == "warehouse"
            or name == "factory" or name == "metalshop"
    end
    if id == "grinder_berg" then
        return name == "electronicstore" or name == "electronicsstorage"
            or name == "radiofactory" or name == "radiostorage"
            or name == "radioshipping"
    end
    if id == "survivalist_locked_horde" then
        return name == "bedroom" or name == "storage"
            or name == "livingroom" or name == "kitchen"
    end
    if id == "garage_rescue_eli_rourke" then
        return name == "garage" or name == "garagestorage"
    end
    if id == "radio_rescue_nate_duvall" then
        return name == "bedroom" or name == "utility"
            or name == "storage"
    end
    if id == "voice_actor_vera_quill" then return name == "bedroom" end
    if id == "milli_tea_and_trouble" then
        -- The sampled ground-floor tile may be a kitchen while the child's
        -- bedroom is upstairs. Milli.siteFor inspects this building's rooms.
        return true
    end
    if id == "pyromaniac_earl_kessler" then return true end
    return false
end

local function captiveCellRoom(name)
    return name == "cells" or name == "prisoncells" or name == "policecells"
        or name == "jailcell" or name == "jailcells"
end

local function shelterRoom(name)
    return type(name) == "string" and (string.find(name, "butcher", 1, true) ~= nil
        or string.find(name, "barn", 1, true) ~= nil
        or string.find(name, "farmstorage", 1, true) ~= nil)
end

local function roadSquare(square)
    local floor, floorCalled = U().call(square, "getFloor")
    local sprite, spriteCalled = U().call(floorCalled and floor or nil, "getSprite")
    local name, nameCalled = U().call(spriteCalled and sprite or nil, "getName")
    if not nameCalled or type(name) ~= "string" then return false end
    name = string.lower(name)
    return string.find(name, "blends_street", 1, true) ~= nil
        or string.find(name, "floors_exterior_street", 1, true) ~= nil
        or string.find(name, "street_", 1, true) == 1
end

local function nearbyZombies(origin)
    local center = point(origin)
    if not center then return 0 end
    local count = 0
    for dx = -5, 5 do
        for dy = -5, 5 do
            if dx * dx + dy * dy <= 25 then
                local square = U().gridSquare(center.x + dx, center.y + dy, center.z)
                local moving, called = U().call(square, "getMovingObjects")
                if called and moving ~= nil then
                    for index = 0, math.min(31, SC.NativeList.size(moving) - 1) do
                        if U().isZombie(SC.NativeList.get(moving, index)) then
                            count = count + 1
                            if count >= 4 then return count end
                        end
                    end
                end
            end
        end
    end
    return count
end

local function churchUnderSiege(square)
    if type(getCell) == "function" and SC.NativeList then
        local okay, cell = pcall(getCell)
        local list = okay and cell and select(1, U().call(cell,
            "getZombieList")) or nil
        if list then
            local sx, sy, sz = U().position(square)
            local count = 0
            for index = 0, math.min(1023, SC.NativeList.size(list) - 1) do
                local zombie = SC.NativeList.get(list, index)
                local x, y, z
                if zombie then x, y, z = U().position(zombie) end
                if x and z == sz and (x - sx) ^ 2 + (y - sy) ^ 2 <= 40 * 40 then
                    count = count + 1
                    if count >= 10 then return true end
                end
            end
            return false
        end
    end
    return nearbyZombies(square) >= 5
end

local function shelterNear(road, player, allowSeen)
    local center = point(road)
    if not center then return nil end
    local visited = {}
    -- A grid finds real rooms between the eight rays without searching the
    -- whole map. One horde candidate checks at most 225 loaded squares.
    for dx = -28, 28, 4 do
        for dy = -28, 28, 4 do
            local x = center.x + dx
            local y = center.y + dy
            local square = U().gridSquare(x, y, center.z)
            local name = roomName(square)
            if shelterRoom(name) then
                local building, called = U().call(square, "getBuilding")
                if called and building and not visited[building] then
                    visited[building] = true
                    local house = SC.Factions.oddballHouseAt(square, player, allowSeen)
                    if house then return house, name end
                end
            end
        end
    end
    return nil
end

local function coopIn(house)
    for _, position in ipairs(house.interior or {}) do
        local square = U().gridSquare(position.x, position.y, position.z or 0)
        local name = roomName(square)
        if name and (string.find(name, "barn", 1, true)
            or string.find(name, "farmstorage", 1, true)
            or string.find(name, "coop", 1, true)
            or string.find(name, "stall", 1, true)) then
            local east = U().gridSquare(position.x + 1, position.y, position.z or 0)
            local south = U().gridSquare(position.x, position.y + 1, position.z or 0)
            local southeast = U().gridSquare(position.x + 1, position.y + 1,
                position.z or 0)
            if roomName(east) == name and roomName(south) == name
                and roomName(southeast) == name
                and U().isSafeSpawnSquare(east)
                and U().isSafeSpawnSquare(south)
                and U().isSafeSpawnSquare(southeast) then
                return { x = position.x, y = position.y, z = position.z or 0,
                    enclosed = true }
            end
        end
    end
    return nil
end

local function animalPostsIn(house, room, player, allowSeen, count, avoid)
    local posts = {}
    local function blocked(position)
        if type(avoid) ~= "table" then return false end
        local list = avoid.x and { avoid } or avoid
        for _, pointToAvoid in ipairs(list) do
            if position.x == pointToAvoid.x and position.y == pointToAvoid.y
                and (position.z or 0) == (pointToAvoid.z or 0) then
                return true
            end
        end
        return false
    end
    for _, position in ipairs(house.interior or {}) do
        local square = U().gridSquare(position.x, position.y,
            position.z or 0)
        if position.z == 0 and roomName(square) == room
            and not blocked(position)
            and candidateUnseen(square, player, allowSeen) then
            posts[#posts + 1] = point(square)
            if #posts == count then return posts end
        end
    end
    return nil
end

local eachObject

local function otherRoomTile(house, spawn)
    local square = U().gridSquare(spawn.x, spawn.y, spawn.z or 0)
    local room = select(1, U().call(square, "getRoom"))
    if not room then return nil end
    for _, position in ipairs(house.interior or {}) do
        if position.z == 0 and (position.x ~= spawn.x or position.y ~= spawn.y) then
            local candidate = U().gridSquare(position.x, position.y, 0)
            if select(1, U().call(candidate, "getRoom")) == room then
                return point(candidate)
            end
        end
    end
    return nil
end

local function partyOpening(house, spawn, kind)
    local room = select(1, U().call(
        U().gridSquare(spawn.x, spawn.y, spawn.z or 0), "getRoom"))
    if not room then return nil end
    local best, bestDistance
    local bounds = house.bounds
    for x = bounds.x1, bounds.x2 do
        for y = bounds.y1, bounds.y2 do
            local square = U().gridSquare(x, y, 0)
            if square then
                eachObject(square, function(object)
                    if U().instanceOf(object, kind == "door"
                        and "IsoDoor" or "IsoWindow") then
                        local north = select(1, U().call(object, "getNorth"))
                        if type(north) == "boolean" then
                            local other = U().gridSquare(x - (north and 0 or 1),
                                y - (north and 1 or 0), 0)
                            local hereRoom = select(1, U().call(square, "getRoom"))
                            local thereRoom = select(1, U().call(other, "getRoom"))
                            if (hereRoom == room) ~= (thereRoom == room) then
                                local index = select(1,
                                    U().call(object, "getObjectIndex"))
                                local distance = (x - spawn.x) ^ 2
                                    + (y - spawn.y) ^ 2
                                if type(index) == "number" and index >= 0
                                    and (not bestDistance or distance < bestDistance) then
                                    best = { x = x, y = y, z = 0,
                                        objectIndex = index, kind = kind }
                                    bestDistance = distance
                                end
                            end
                        end
                    end
                    return false
                end)
            end
        end
    end
    return best
end

local function rabbitSpawns(house, spawn, player, allowSeen)
    local square = U().gridSquare(spawn.x, spawn.y, 0)
    local room = select(1, U().call(square, "getRoom"))
    if not room then return nil end
    local positions = {}
    for _, position in ipairs(house.interior or {}) do
        if position.z == 0 and (position.x ~= spawn.x or position.y ~= spawn.y) then
            local candidate = U().gridSquare(position.x, position.y, 0)
            if select(1, U().call(candidate, "getRoom")) == room
                and candidateUnseen(candidate, player, allowSeen) then
                positions[#positions + 1] = point(candidate)
                if #positions == 10 then return positions end
            end
        end
    end
    return nil
end

local function nearbyTruck(house)
    if type(getCell) ~= "function" or type(house) ~= "table" then return nil end
    local okay, cell = pcall(getCell)
    if not okay or cell == nil then return nil end
    local vehicles, called = U().call(cell, "getVehicles")
    if not called then vehicles, called = U().call(cell, "getVehicleList") end
    if not called or vehicles == nil then return nil end
    local bounds = house.bounds
    local anchor = house.anchor
    if type(bounds) ~= "table" or type(anchor) ~= "table" then return nil end
    local best, bestDistanceSq
    for index = 0, math.min(255, SC.NativeList.size(vehicles) - 1) do
        local vehicle = SC.NativeList.get(vehicles, index)
        local name, nameCalled = U().call(vehicle, "getScriptName")
        name = nameCalled and type(name) == "string" and string.lower(name) or ""
        if string.find(name, "truck", 1, true)
            or string.find(name, "pickup", 1, true) then
            local x, y, z = U().position(vehicle)
            if tonumber(x) and tonumber(y) and math.floor(tonumber(z) or 0)
                == math.floor(tonumber(anchor.z) or 0) then
                local dx = x < bounds.x1 and bounds.x1 - x
                    or x > bounds.x2 and x - bounds.x2 or 0
                local dy = y < bounds.y1 and bounds.y1 - y
                    or y > bounds.y2 and y - bounds.y2 or 0
                local distanceSq = dx * dx + dy * dy
                local square = U().gridSquare(math.floor(x), math.floor(y),
                    math.floor(tonumber(z) or 0))
                if square and distanceSq <= 16 * 16
                    and (bestDistanceSq == nil or distanceSq < bestDistanceSq) then
                    best = { x = math.floor(x), y = math.floor(y),
                        z = math.floor(tonumber(z) or 0) }
                    bestDistanceSq = distanceSq
                end
            end
        end
    end
    return best
end

Oddballs._nearbyTruckForTests = nearbyTruck

local function objectsAt(square)
    local objects, called = U().call(square, "getObjects")
    return called and objects or nil
end

eachObject = function(square, visitor)
    for _, getter in ipairs({ "getObjects", "getSpecialObjects" }) do
        local objects = getter == "getObjects" and objectsAt(square)
            or select(1, U().call(square, getter))
        if objects then
            for index = 0, math.min(255, SC.NativeList.size(objects) - 1) do
                if visitor(SC.NativeList.get(objects, index), index) == true then
                    return true
                end
            end
        end
    end
    return false
end

local function altarIn(house, spawn)
    for x = house.bounds.x1, house.bounds.x2 do
        for y = house.bounds.y1, house.bounds.y2 do
            local square = U().gridSquare(x, y, 0)
            if roomName(square) == "church" then
                local found = eachObject(square, function(object)
                    local sprite = select(1, U().call(object, "getSprite"))
                    local name = select(1, U().call(sprite, "getName"))
                    local objectName = select(1, U().call(object, "getName"))
                    local label = string.lower(tostring(name or "") .. " "
                        .. tostring(objectName or ""))
                    return string.find(label, "altar", 1, true) ~= nil
                        or string.find(label, "pulpit", 1, true) ~= nil
                end)
                if found then
                    for _, delta in ipairs({ { 0, 0 }, { 0, 1 }, { 1, 0 },
                        { 0, -1 }, { -1, 0 }, { 1, 1 }, { -1, 1 },
                        { 1, -1 }, { -1, -1 } }) do
                        local stand = U().gridSquare(x + delta[1], y + delta[2], 0)
                        if roomName(stand) == "church"
                            and U().isSafeSpawnSquare(stand) then
                            return point(stand)
                        end
                    end
                end
            end
        end
    end
    return spawn
end

local function vestryIn(house, building)
    for x = house.bounds.x1, house.bounds.x2 do
        for y = house.bounds.y1, house.bounds.y2 do
            local square = U().gridSquare(x, y, 0)
            if square and select(1, U().call(square, "getBuilding")) == building then
                -- The ceremony later resolves the saved door by square. Only
                -- use a square with one distinct door so it cannot open a
                -- different door at a junction.
                local oneDoor, multipleDoors
                eachObject(square, function(object)
                    if U().instanceOf(object, "IsoDoor") then
                        if oneDoor and oneDoor ~= object then multipleDoors = true end
                        oneDoor = oneDoor or object
                    end
                    return false
                end)
                if oneDoor and not multipleDoors then
                    local open, openCalled = U().call(oneDoor, "IsOpen")
                    if not openCalled then
                        open, openCalled = U().call(oneDoor, "isOpen")
                    end
                    local opposite = select(1, U().call(oneDoor, "getOppositeSquare"))
                    if openCalled and open ~= true and opposite
                        and select(1, U().call(opposite, "getBuilding")) == building then
                        local here, there = roomName(square), roomName(opposite)
                        local side = here == "church" and there ~= "church" and opposite
                            or there == "church" and here ~= "church" and square or nil
                        local sideName = roomName(side)
                        if side and sideName and sideName ~= "bathroom"
                            and U().isSafeSpawnSquare(side) then
                            return point(side), point(square)
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function separated(positions, candidate, minimumSquared)
    for _, existing in ipairs(positions) do
        local dx, dy = existing.x - candidate.x, existing.y - candidate.y
        if existing.z == candidate.z and dx * dx + dy * dy < minimumSquared then
            return false
        end
    end
    return true
end

local function cultPositions(house, player, allowSeen, spawn, count,
    wantedRoom, spacing)
    local positions = { spawn }
    wantedRoom = wantedRoom or "church"
    spacing = spacing or 4
    for _, position in ipairs(house.interior or {}) do
        if #positions >= count then break end
        local square = U().gridSquare(position.x, position.y, position.z or 0)
        local candidate = square and point(square)
        if candidate and roomName(square) == wantedRoom
            and candidateUnseen(square, player, allowSeen)
            and separated(positions, candidate, spacing) then
            positions[#positions + 1] = candidate
        end
    end
    return #positions >= count and positions or nil
end

local function exteriorWindow(square, building)
    local x, y, z = U().position(square)
    if x == nil then return false end
    for _, delta in ipairs({ { 0, 0 }, { -1, 0 }, { 1, 0 },
        { 0, -1 }, { 0, 1 } }) do
        local holder = U().gridSquare(x + delta[1], y + delta[2], z or 0)
        if eachObject(holder, function(object)
            if not U().instanceOf(object, "IsoWindow") then return false end
            local opposite = select(1, U().call(object, "getOppositeSquare"))
            local holderBuilding = select(1, U().call(holder, "getBuilding"))
            local oppositeBuilding = select(1, U().call(opposite, "getBuilding"))
            return holderBuilding == building and oppositeBuilding ~= building
                or oppositeBuilding == building and holderBuilding ~= building
        end) then return true end
    end
    return false
end

local function purdyPerches(house, building, player, allowSeen)
    local positions = {}
    for x = house.bounds.x1, house.bounds.x2 do
        for y = house.bounds.y1, house.bounds.y2 do
            local square = U().gridSquare(x, y, 1)
            local candidate = square and point(square)
            if candidate and select(1, U().call(square, "getBuilding"))
                == building and candidateUnseen(square, player, allowSeen)
                and exteriorWindow(square, building)
                and separated(positions, candidate, 4) then
                positions[#positions + 1] = candidate
                if #positions == 3 then return positions end
            end
        end
    end
    return nil
end

local function duelGroundNear(house, building)
    for _, opening in ipairs(house.openings or {}) do
        if opening.kind == "door" then
            for radius = 7, 9 do
                for dx = -radius, radius do
                    for _, dy in ipairs({ -radius, radius }) do
                        local square = U().gridSquare(opening.x + dx,
                            opening.y + dy, opening.z or 0)
                        if square and U().isSafeSpawnSquare(square)
                            and select(1, U().call(square, "getBuilding"))
                                ~= building then
                            return point(square)
                        end
                    end
                end
            end
        end
    end
    return nil
end

local houseRooms = {
    livingroom = true, kitchen = true, bedroom = true,
    diningroom = true, hallway = true, laundry = true,
}

local MAIL_RADII = { 24, 40, 56, 72, 96, 120, 144 }
local MAIL_OFFSETS = {
    { 0, 0 }, { 6, 0 }, { -6, 0 }, { 0, 6 }, { 0, -6 },
}

local function mailTargetsNear(house, building, player)
    local anchor = house.anchor
    local visited, targets = {}, {}
    local function consider(x, y)
        local square = U().gridSquare(x, y, 0)
        local name = roomName(square)
        if not houseRooms[name] then return false end
        local other = select(1, U().call(square, "getBuilding"))
        if not other or other == building or visited[other] then return false end
        visited[other] = true
        local destination = SC.Factions.oddballHouseAt(square, player, true)
        if not destination or destination.id == house.id then return false end
        local door
        for _, opening in ipairs(destination.openings or {}) do
            if opening.kind == "door" then door = opening break end
        end
        if not door then return false end
        local inside
        for _, position in ipairs(destination.interior or {}) do
            if not inside then inside = position end
            local dx, dy = position.x - door.x, position.y - door.y
            local prior = inside and ((inside.x - door.x) ^ 2
                + (inside.y - door.y) ^ 2) or -1
            if dx * dx + dy * dy > prior then inside = position end
        end
        if not inside then return false end
        local label = SC.Factions.describeLocation(door)
        targets[#targets + 1] = {
            x = door.x, y = door.y, z = door.z or 0,
            houseId = destination.id,
            label = label and label.address or ("House near "
                .. tostring(door.x) .. ", " .. tostring(door.y)),
            inside = { x = inside.x, y = inside.y, z = inside.z or 0 },
        }
        return #targets >= 4
    end
    -- Sparse, bounded loaded-square search. The expensive building descriptor
    -- runs once per discovered house, and the pass stops at four real doors.
    for _, radius in ipairs(MAIL_RADII) do
        for angleIndex = 0, 31 do
            local angle = angleIndex * math.pi / 16
            local centerX = math.floor(anchor.x + math.cos(angle) * radius)
            local centerY = math.floor(anchor.y + math.sin(angle) * radius)
            for _, offset in ipairs(MAIL_OFFSETS) do
                if consider(centerX + offset[1], centerY + offset[2]) then
                    local home = table.remove(targets, 4)
                    local homeInside = home.inside
                    home.inside = nil
                    for _, target in ipairs(targets) do target.inside = nil end
                    return targets, home, homeInside
                end
            end
        end
    end
    return nil, nil, nil
end

-- The horde is placed only in a real, separate room. Its one closed door
-- divides the room from Caleb's reachable standing square.
local function survivalistSite(house, square, player, allowSeen)
    local rooms, choices = {}, {}
    for _, position in ipairs(house.interior or {}) do
        local tile = U().gridSquare(position.x, position.y, position.z or 0)
        local room = tile and select(1, U().call(tile, "getRoom"))
        local name = roomName(tile)
        if room and (name == "bedroom" or name == "storage"
            or name == "livingroom" or name == "kitchen")
            and candidateUnseen(tile, player, allowSeen) then
            if not rooms[room] then
                rooms[room] = { room = room, tiles = {} }
                choices[#choices + 1] = rooms[room]
            end
            rooms[room].tiles[#rooms[room].tiles + 1] = point(tile)
        end
    end
    for _, choice in ipairs(choices) do
        if #choice.tiles >= 4 and #choice.tiles <= 28 then
            local doors, windows, unsafeOpening = {}, 0, false
            local visited = {}
            local x1, x2, y1, y2
            for _, tile in ipairs(choice.tiles) do
                x1 = math.min(x1 or tile.x, tile.x)
                x2 = math.max(x2 or tile.x, tile.x)
                y1 = math.min(y1 or tile.y, tile.y)
                y2 = math.max(y2 or tile.y, tile.y)
            end
            for x = x1 - 1, x2 + 1 do
                for y = y1 - 1, y2 + 1 do
                    local tile = U().gridSquare(x, y, 0)
                    if tile then
                        U().squareObjects(tile, function(object, index)
                            if visited[object] then return end
                            visited[object] = true
                            local door = U().instanceOf(object, "IsoDoor")
                            local window = U().instanceOf(object, "IsoWindow")
                            if not door and not window then return end
                            local north = select(1, U().call(object, "getNorth"))
                            if type(north) ~= "boolean" then return end
                            local other = U().gridSquare(x - (north and 0 or 1),
                                y - (north and 1 or 0), 0)
                            local hereRoom = select(1, U().call(tile, "getRoom"))
                            local thereRoom = select(1, U().call(other, "getRoom"))
                            if (hereRoom == choice.room) ==
                                (thereRoom == choice.room) then return end
                            if window then
                                windows = windows + 1
                                if select(1, U().call(object, "IsOpen")) == true
                                    or select(1, U().call(object, "isSmashed")) == true then
                                    unsafeOpening = true
                                end
                            elseif select(1, U().call(object, "IsOpen")) == false then
                                local outside = hereRoom == choice.room and other
                                    or tile
                                if candidateUnseen(outside, player, allowSeen) then
                                    doors[#doors + 1] = {
                                        door = { x = x, y = y, z = 0,
                                            objectIndex = index, kind = "door" },
                                        outside = point(outside) }
                                end
                            else
                                unsafeOpening = true
                            end
                        end, 96)
                    end
                end
            end
            if #doors == 1 and windows <= 2 and not unsafeOpening then
                return { kind = "resident", room = roomName(square),
                    house = house, anchor = point(square) or house.anchor,
                    spawn = doors[1].outside,
                    sealedRoom = choice.tiles[1],
                    roomDoor = doors[1].door,
                    hordeSpawns = choice.tiles }
            end
        end
    end
    return nil
end

local function siteForResident(square, player, definition, name, allowSeen)
    if not isResidentRoom(definition.id, name) then return nil end
    local house = SC.Factions.oddballHouseAt(square, player, allowSeen)
    if not house then return nil end
    if definition.id == "milli_tea_and_trouble" then
        local milli = SC.OddballMilli
        if type(milli) ~= "table" or type(milli.siteFor) ~= "function" then
            return nil
        end
        return milli.siteFor(house, player, allowSeen)
    end
    if definition.id == "survivalist_locked_horde" then
        return survivalistSite(house, square, player, allowSeen)
    end
    if definition.id == "seer_aunt_velma_crisp" and name == "bedroom" then
        local bounds = house.bounds or {}
        local width = (tonumber(bounds.x2) or 0) - (tonumber(bounds.x1) or 0) + 1
        local height = (tonumber(bounds.y2) or 0) - (tonumber(bounds.y1) or 0) + 1
        if width * height > 80 then return nil end
    end
    if definition.id == "preacher_reverend_amos"
        and not churchUnderSiege(square) then return nil end
    local building = select(1, U().call(square, "getBuilding"))
    local spawn
    local captiveSpawns, distinctCells = {}, {}
    for _, position in ipairs(house.interior or {}) do
        local option = U().gridSquare(position.x, position.y, position.z or 0)
        local optionRoom = roomName(option)
        local dutyRoom = not spawn and isResidentRoom(definition.id, optionRoom)
        local cellRoom = definition.captives == true and captiveCellRoom(optionRoom)
        if (dutyRoom or cellRoom)
            and candidateUnseen(option, player, allowSeen) then
            if dutyRoom then
                spawn = point(option)
            elseif cellRoom then
                local room = select(1, U().call(option, "getRoom"))
                local cellKey = room or optionRoom
                if not distinctCells[cellKey] then
                    distinctCells[cellKey] = true
                    captiveSpawns[#captiveSpawns + 1] = point(option)
                end
            end
        end
        if spawn and definition.captives ~= true then break end
    end
    if not spawn then return nil end
    if definition.captives == true and #captiveSpawns == 0 then return nil end
    local site = { kind = "resident", room = name, house = house,
        anchor = point(square) or house.anchor, spawn = spawn }
    if definition.id == "garage_rescue_eli_rourke"
        or definition.id == "radio_rescue_nate_duvall" then
        local opening = partyOpening(house, spawn, "door")
        local holder = opening and U().gridSquare(opening.x,
            opening.y, opening.z or 0)
        local objects = holder and select(1, U().call(holder, "getObjects"))
        local door = objects and SC.NativeList
            and SC.NativeList.get(objects, opening.objectIndex) or nil
        if not door or select(1, U().call(door, "IsOpen")) ~= false then
            return nil
        end
        site.rescueDoor = opening
        if definition.id == "garage_rescue_eli_rourke" then
            local room = select(1, U().call(
                U().gridSquare(spawn.x, spawn.y, spawn.z or 0), "getRoom"))
            local best, bestScore
            for _, position in ipairs(house.interior or {}) do
                local candidate = U().gridSquare(position.x, position.y,
                    position.z or 0)
                if room and candidate and candidateUnseen(candidate,
                    player, allowSeen)
                    and select(1, U().call(candidate, "getRoom")) == room then
                    local edgeCount = 0
                    for _, step in ipairs({ { 1, 0 }, { -1, 0 },
                        { 0, 1 }, { 0, -1 } }) do
                        local neighbor = U().gridSquare(position.x + step[1],
                            position.y + step[2], position.z or 0)
                        if neighbor and select(1, U().call(neighbor,
                            "getRoom")) ~= room then edgeCount = edgeCount + 1 end
                    end
                    local doorDistance = (position.x - opening.x) ^ 2
                        + (position.y - opening.y) ^ 2
                    if edgeCount > 0 and doorDistance >= 4 then
                        local score = edgeCount * 100
                            + math.min(doorDistance, 25)
                        if not bestScore or score > bestScore then
                            best, bestScore = point(candidate), score
                        end
                    end
                end
            end
            if not best then return nil end
            site.spawn = best
        end
    end
    if definition.id == "pyromaniac_earl_kessler" then
        local bounds = house.bounds or {}
        if not bounds.x1 or not bounds.x2 or not bounds.y1 or not bounds.y2
            or (bounds.x2 - bounds.x1 + 1) * (bounds.y2 - bounds.y1 + 1) > 900 then
            return nil
        end
        local spawnSquare = U().gridSquare(spawn.x, spawn.y, spawn.z or 0)
        local spawnRoom = select(1, U().call(spawnSquare, "getRoom"))
        local candidates = {}
        for _, position in ipairs(house.interior or {}) do
            local option = U().gridSquare(position.x, position.y, position.z or 0)
            local room = option and select(1, U().call(option, "getRoom"))
            local dx, dy = position.x - spawn.x, position.y - spawn.y
            if option and spawnRoom and room == spawnRoom
                and dx * dx + dy * dy <= 25 and dx * dx + dy * dy > 0
                and U().isSquareFree(option) then
                candidates[#candidates + 1] = point(option)
            end
        end
        if #candidates < 2 then return nil end
        local hash = type(U().stableHash) == "function"
            and U().stableHash(tostring(house.id) .. ":pyro-fuel") or 0
        local wanted = math.min(#candidates, 2 + hash % 5)
        site.fuelPosts = {}
        local start = hash % #candidates
        local stride = math.max(1, math.floor(#candidates / wanted))
        for index = 1, wanted do
            site.fuelPosts[index] = candidates[
                (start + (index - 1) * stride) % #candidates + 1]
        end
    end
    if definition.captives == true then
        local count = 1
        local hash = type(U().stableHash) == "function"
            and U().stableHash(tostring(house.id) .. ":deputy-captives") or 0
        if #captiveSpawns >= 2 and hash % 2 == 0 then count = 2 end
        site.captiveSpawns = {}
        for index = 1, count do
            site.captiveSpawns[index] = captiveSpawns[index]
        end
    end
    if definition.id == "voice_actor_vera_quill" then
        local opening = partyOpening(house, spawn, "door")
        local holder = opening and U().gridSquare(opening.x,
            opening.y, opening.z or 0)
        local objects = holder and select(1, U().call(holder, "getObjects"))
        local door = objects and SC.NativeList
            and SC.NativeList.get(objects, opening.objectIndex) or nil
        if not door or select(1, U().call(door, "IsOpen")) ~= false then
            return nil
        end
        local bedroom = select(1, U().call(
            U().gridSquare(spawn.x, spawn.y, spawn.z or 0), "getRoom"))
        for _, windowPost in ipairs(house.openings or {}) do
            if windowPost.kind == "window" then
                local windowSquare = U().gridSquare(windowPost.x,
                    windowPost.y, windowPost.z or 0)
                local windowObjects = windowSquare and select(1,
                    U().call(windowSquare, "getObjects"))
                local window = windowObjects and SC.NativeList
                    and SC.NativeList.get(windowObjects,
                        windowPost.objectIndex) or nil
                local north = window and select(1,
                    U().call(window, "getNorth"))
                if type(north) == "boolean" then
                    local opposite = U().gridSquare(windowPost.x
                        - (north and 0 or 1), windowPost.y
                        - (north and 1 or 0), windowPost.z or 0)
                    local here = select(1, U().call(windowSquare, "getRoom"))
                    local there = select(1, U().call(opposite, "getRoom"))
                    if (here == bedroom or there == bedroom)
                        and (select(1, U().call(window, "IsOpen")) == true
                            or select(1, U().call(window,
                                "isSmashed")) == true) then
                        return nil
                    end
                end
            end
        end
        site.bedroomDoor = opening
    end
    if definition.id == "digger_merle_lusby" then
        local bounds = house.bounds or {}
        local floorIsNatural = function(option)
            local floor = option and select(1, U().call(option, "getFloor"))
            local texture = floor and select(1,
                U().call(floor, "getTextureName")) or ""
            texture = tostring(texture or "")
            return string.sub(texture, 1, 23) == "floors_exterior_natural"
                or string.sub(texture, 1, 17) == "blends_natural_01"
        end
        for _, side in ipairs({ -1, 1 }) do
            if site.grave then break end
            for gap = 2, 8 do
                if site.grave then break end
                local y = side < 0 and bounds.y1 - gap or bounds.y2 + gap
                for x = bounds.x1, bounds.x2 do
                    local target = U().gridSquare(x, y, 0)
                    local partner = U().gridSquare(x - 1, y, 0)
                    local post = U().gridSquare(x, y + side, 0)
                    if target and partner and post
                        and floorIsNatural(target)
                        and floorIsNatural(partner)
                        and roomName(target) == nil
                        and roomName(partner) == nil
                        and U().isSquareFree(target)
                        and U().isSquareFree(partner)
                        and candidateUnseen(post, player, allowSeen) then
                        site.grave = point(target)
                        site.spawn = point(post)
                        break
                    end
                end
            end
        end
        if not site.grave then return nil end
    elseif definition.id == "cult_brother_silas" then
        local desired = tonumber(definition.memberCountMin) or 3
        local hash = type(U().stableHash) == "function"
            and U().stableHash(tostring(house.id) .. ":cult-count") or 0
        if hash % 2 == 0 then desired = tonumber(definition.memberCountMax) or desired end
        site.memberSpawns = cultPositions(house, player, allowSeen, spawn, desired)
            or (desired > 3 and cultPositions(house, player, allowSeen, spawn, 3))
        if not site.memberSpawns then return nil end
        site.altar = altarIn(house, spawn)
    elseif definition.id == "wedding_lonnie_tackett" then
        site.altar = altarIn(house, spawn)
        site.vestry, site.vestryDoor = vestryIn(house, building)
        if not site.vestry or not site.vestryDoor then return nil end
    elseif definition.id == "postman_virgil_toombs" then
        site.mailTargets, site.homeTarget, site.homeZombie =
            mailTargetsNear(house, building, player)
        if not site.mailTargets or not site.homeTarget or not site.homeZombie then
            return nil
        end
    elseif definition.id == "duelist_clem_sutter" then
        site.duelGround = duelGroundNear(house, building)
        if not site.duelGround then return nil end
    elseif definition.id == "sniper_purdy_clan" then
        site.tradePost = spawn
        site.memberSpawns = purdyPerches(house, building, player, allowSeen)
        if not site.memberSpawns then return nil end
        site.spawn = site.memberSpawns[1]
    elseif definition.id == "christmas_kris_kimbrough" then
        for _, position in ipairs(house.interior or {}) do
            local candidate = U().gridSquare(position.x, position.y,
                position.z or 0)
            local candidateRoom = roomName(candidate)
            if (candidateRoom == "storage" or candidateRoom == "stockroom"
                or candidateRoom == "toystorage")
                and candidateUnseen(candidate, player, allowSeen)
                and (position.x - spawn.x) ^ 2
                    + (position.y - spawn.y) ^ 2 >= 9 then
                site.elvesRoom = point(candidate)
                break
            end
        end
        if not site.elvesRoom then return nil end
    elseif definition.id == "watcher_pettigrew_lusk" then
        site.neighbors = {}
        for _, other in ipairs(SC.Factions.list(false)) do
            local anchor = other.house and other.house.anchor
            local nearX, nearY = anchor and tonumber(anchor.x),
                anchor and tonumber(anchor.y)
            if other.oddball == nil and other.lifecycle ~= "destroyed"
                and nearX and nearY and other.house
                and other.house.id ~= house.id then
                local distance = (nearX - spawn.x) ^ 2
                    + (nearY - spawn.y) ^ 2
                if distance >= 25 and distance <= 80 * 80 then
                    site.neighbors[#site.neighbors + 1] = {
                        id = other.id, x = math.floor(nearX),
                        y = math.floor(nearY), z = tonumber(anchor.z) or 0,
                        name = other.name or "the next house" }
                    if #site.neighbors == 3 then break end
                end
            end
        end
        if #site.neighbors < 2 then return nil end
    elseif definition.id == "slot_lester_voss" then
        local door
        for _, opening in ipairs(house.openings or {}) do
            if opening.kind == "door" then door = opening break end
        end
        if not door then return nil end
        local holder = U().gridSquare(door.x, door.y, door.z or 0)
        local objects = holder and select(1, U().call(holder, "getObjects"))
        local doorObject = objects and SC.NativeList
            and SC.NativeList.get(objects, door.objectIndex) or nil
        local north = doorObject and select(1,
            U().call(doorObject, "getNorth"))
        if type(north) ~= "boolean" then return nil end
        local opposite = U().gridSquare(door.x - (north and 0 or 1),
            door.y - (north and 1 or 0), door.z or 0)
        local outside = roomName(holder) == nil and holder
            or opposite and roomName(opposite) == nil and opposite or nil
        if not outside then return nil end
        local wifePost
        for _, position in ipairs(house.interior or {}) do
            local option = U().gridSquare(position.x, position.y,
                position.z or 0)
            if option and candidateUnseen(option, player, allowSeen)
                and (position.x - spawn.x) ^ 2
                    + (position.y - spawn.y) ^ 2 >= 4 then
                local distance = (position.x - door.x) ^ 2
                    + (position.y - door.y) ^ 2
                if not wifePost or distance < wifePost.distance then
                    wifePost = { position = point(option), distance = distance }
                end
            end
        end
        if not wifePost then return nil end
        site.slotDoor = door
        site.slotOutside = point(outside)
        site.memberSpawns = { spawn, wifePost.position }
    elseif definition.id == "tupelo_boys" then
        site.memberSpawns = cultPositions(house, player, allowSeen,
            spawn, 4, "bar", 2) or cultPositions(house, player,
                allowSeen, spawn, 3, "bar", 2)
        if not site.memberSpawns then return nil end
    elseif definition.id == "rosewood_auxiliary" then
        local bounds = house.bounds or {}
        local area = ((tonumber(bounds.x2) or 0)
            - (tonumber(bounds.x1) or 0) + 1)
            * ((tonumber(bounds.y2) or 0)
                - (tonumber(bounds.y1) or 0) + 1)
        if area < 90 then return nil end
        site.memberSpawns = cultPositions(house, player,
            allowSeen, spawn, 3, "kitchen", 2)
        if not site.memberSpawns then return nil end
    elseif definition.id == "bledsoe_brothers_still" then
        local bounds = house.bounds or {}
        local area = ((tonumber(bounds.x2) or 0)
            - (tonumber(bounds.x1) or 0) + 1)
            * ((tonumber(bounds.y2) or 0)
                - (tonumber(bounds.y1) or 0) + 1)
        if area > 90 then return nil end
        site.memberSpawns = cultPositions(house, player,
            allowSeen, spawn, 2, name, 2)
        if not site.memberSpawns then return nil end
        local waterNearby = false
        for radius = 4, 24, 4 do
            for angle = 0, 15 do
                local theta = angle * math.pi / 8
                local water = U().gridSquare(
                    math.floor(spawn.x + math.cos(theta) * radius),
                    math.floor(spawn.y + math.sin(theta) * radius), 0)
                if water and SC.Topology and type(SC.Topology.squareIsWater)
                    == "function" and SC.Topology.squareIsWater(water) then
                    waterNearby = true; break
                end
            end
            if waterNearby then break end
        end
        if not waterNearby then return nil end
    elseif definition.id == "crabtree_sheep_farm" then
        site.memberSpawns = cultPositions(house, player, allowSeen,
            spawn, 2, name, 2)
        site.animalSpawns = animalPostsIn(house, name, player,
            allowSeen, 6, site.memberSpawns)
        if not site.memberSpawns or not site.animalSpawns then return nil end
    elseif definition.id == "jedediah_cattle_drive" then
        site.animalSpawns = animalPostsIn(house, name, player,
            allowSeen, 4, spawn)
        if not site.animalSpawns then return nil end
        for radius = 6, 30, 3 do
            for angle = 0, 15 do
                local theta = angle * math.pi / 8
                local trail = U().gridSquare(
                    math.floor(spawn.x + math.cos(theta) * radius),
                    math.floor(spawn.y + math.sin(theta) * radius), 0)
                if trail and roadSquare(trail) then
                    site.trail = point(trail); break
                end
            end
            if site.trail then break end
        end
        if not site.trail then return nil end
    elseif definition.id == "gideon_mister_buttons" then
        local birdPost = animalPostsIn(house, name, player,
            allowSeen, 1, spawn)
        site.animalSpawns = birdPost
        site.kitchenDoor = partyOpening(house, spawn, "door")
        if not site.kitchenDoor or not site.animalSpawns then return nil end
    elseif definition.id == "renfro_rat_king" then
        if partyOpening(house, spawn, "window") then return nil end
        local room = select(1, U().call(U().gridSquare(spawn.x,
            spawn.y, spawn.z or 0), "getRoom"))
        site.animalSpawns = {}
        for _, position in ipairs(house.interior or {}) do
            local option = U().gridSquare(position.x, position.y,
                position.z or 0)
            if option and (position.x ~= spawn.x or position.y ~= spawn.y
                or position.z ~= spawn.z)
                and select(1, U().call(option, "getRoom")) == room
                and candidateUnseen(option, player, allowSeen) then
                site.animalSpawns[#site.animalSpawns + 1] = point(option)
                if #site.animalSpawns == 8 then break end
            end
        end
        if #site.animalSpawns < 8 then return nil end
    elseif definition.id == "trestle_goatman" then
        local woods
        for radius = 8, 24, 4 do
            for angle = 0, 15 do
                local theta = angle * math.pi / 8
                local candidate = U().gridSquare(
                    math.floor(spawn.x + math.cos(theta) * radius),
                    math.floor(spawn.y + math.sin(theta) * radius), 0)
                if candidate and roomName(candidate) == nil
                    and (candidateUnseen(candidate, player, allowSeen)
                        or select(1, U().call(candidate, "getTree"))) then
                    local floor = select(1, U().call(candidate, "getFloor"))
                    local sprite = floor and select(1,
                        U().call(floor, "getSprite"))
                    local texture = sprite and select(1,
                        U().call(sprite, "getName")) or ""
                    if candidateUnseen(candidate, player, allowSeen)
                        and type(texture) == "string"
                        and string.find(string.lower(texture), "rail", 1, true) then
                        site.haunt = point(candidate)
                        site.hauntKind = "rail"
                        break
                    end
                    if not woods and select(1,
                        U().call(candidate, "getTree")) then
                        for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
                            { 0, 1 }, { 0, -1 } }) do
                            local adjacent = U().gridSquare(
                                math.floor(spawn.x + math.cos(theta) * radius)
                                    + offset[1],
                                math.floor(spawn.y + math.sin(theta) * radius)
                                    + offset[2], 0)
                            if adjacent and candidateUnseen(adjacent,
                                player, allowSeen) then
                                woods = point(adjacent); break
                            end
                        end
                    end
                end
            end
            if site.haunt then break end
        end
        site.haunt = site.haunt or woods
        site.hauntKind = site.hauntKind or "woods"
        if not site.haunt then return nil end
    elseif definition.id == "tolliver_farm_siege" then
        local bounds = house.bounds or {}
        local area = ((tonumber(bounds.x2) or 0)
            - (tonumber(bounds.x1) or 0) + 1)
            * ((tonumber(bounds.y2) or 0)
                - (tonumber(bounds.y1) or 0) + 1)
        if area < 100 then return nil end
        site.memberSpawns = cultPositions(house, player, allowSeen,
            spawn, 4, name, 2)
        if not site.memberSpawns then return nil end
    elseif definition.id == "sleeping_it_off" then
        for _, position in ipairs(house.interior or {}) do
            local tile = U().gridSquare(position.x, position.y,
                position.z or 0)
            if roomName(tile) == name and not site.bed then
                U().squareObjects(tile, function(object, index)
                    local label = select(1, U().call(object, "getName"))
                    local sprite = select(1, U().call(object, "getSprite"))
                    local spriteName = sprite and select(1,
                        U().call(sprite, "getName")) or ""
                    label = string.lower(tostring(label or ""))
                    spriteName = string.lower(tostring(spriteName or ""))
                    if string.find(label, "bed", 1, true)
                        or string.find(spriteName,
                            "furniture_bedding", 1, true) then
                        site.bed = { x = position.x, y = position.y,
                            z = position.z or 0, objectIndex = index }
                        return false
                    end
                end, 64)
            end
            if site.bed then break end
        end
        if not site.bed then return nil end
    elseif definition.id == "man_in_the_chair" then
        local frontDoor = house.primaryEntry
        if not frontDoor then return nil end
        for _, position in ipairs(house.interior or {}) do
            local tile = U().gridSquare(position.x, position.y,
                position.z or 0)
            if roomName(tile) == "livingroom" and not site.chair
                and (position.x - frontDoor.x) ^ 2
                    + (position.y - frontDoor.y) ^ 2 <= 12 * 12 then
                U().squareObjects(tile, function(object, index)
                    local label = select(1, U().call(object, "getName"))
                    local sprite = select(1, U().call(object, "getSprite"))
                    local spriteName = sprite and select(1,
                        U().call(sprite, "getName")) or ""
                    label = string.lower(tostring(label or ""))
                    spriteName = string.lower(tostring(spriteName or ""))
                    if string.find(label, "armchair", 1, true)
                        or string.find(spriteName,
                            "furniture_seating_indoor", 1, true) then
                        site.chair = { x = position.x, y = position.y,
                            z = position.z or 0, objectIndex = index }
                        return false
                    end
                end, 64)
            end
            if site.chair then break end
        end
        for _, position in ipairs(house.interior or {}) do
            local tile = U().gridSquare(position.x, position.y,
                position.z or 0)
            if roomName(tile) == "bedroom" and position.z == spawn.z
                and candidateUnseen(tile, player, allowSeen) then
                local door = partyOpening(house, point(tile), "door")
                if door then
                    site.bedroom = point(tile)
                    site.bedroomDoor = door
                    break
                end
            end
        end
        if not site.chair or not site.bedroomDoor then return nil end
    elseif definition.id == "tommy_two_lengths" then
        site.animalSpawns = animalPostsIn(house, name, player,
            allowSeen, 1, spawn)
        if not site.animalSpawns then return nil end
        for radius = 12, 60, 4 do
            for angle = 0, 15 do
                local theta = angle * math.pi / 8
                local road = U().gridSquare(
                    math.floor(spawn.x + math.cos(theta) * radius),
                    math.floor(spawn.y + math.sin(theta) * radius), 0)
                if road and roadSquare(road)
                    and candidateUnseen(road, player, allowSeen) then
                    site.racePost = point(road); break
                end
            end
            if site.racePost then break end
        end
        if not site.racePost then return nil end
    elseif definition.id == "gordon_pettibone" then
        -- Household descriptors deliberately keep ground-floor interiors.
        -- Search the same building footprint at z=-1 for Gordon's bunker.
        local bounds = house.bounds or {}
        for x = bounds.x1, bounds.x2 do
            for y = bounds.y1, bounds.y2 do
                local tile = U().gridSquare(x, y, -1)
                local room = roomName(tile)
                if tile and (room == "basement" or room == "cellar"
                    or room == "storage" or room == "utility")
                    and candidateUnseen(tile, player, allowSeen) then
                    U().squareObjects(tile, function(object, index)
                        if site.bunkerDoor or not U().instanceOf(object,
                            "IsoDoor") then return end
                        local north = select(1, U().call(object, "getNorth"))
                        if type(north) ~= "boolean" then return end
                        local other = U().gridSquare(x - (north and 0 or 1),
                            y - (north and 1 or 0), -1)
                        if not other or roomName(other) == room
                            or not U().isSafeSpawnSquare(other) then return end
                        site.bunkerDoor = { x = x, y = y, z = -1,
                            objectIndex = index }
                        site.bunkerOutside = point(other)
                        site.spawn = point(tile)
                        return false
                    end, 64)
                end
                if site.bunkerDoor then break end
            end
            if site.bunkerDoor then break end
        end
        if not site.bunkerDoor then return nil end
    elseif definition.id == "morton_buster" then
        -- The stage changes only if Rusty already owns a theatre.
        local rustySeeded = state.seeded.ringmaster_rusty_pell ~= nil
        if rustySeeded and name ~= "bar"
            or not rustySeeded and name ~= "theatre"
                and name ~= "theater" then return nil end
        for _, position in ipairs(house.interior or {}) do
            local tile = U().gridSquare(position.x, position.y,
                position.z or 0)
            if roomName(tile) == name then
                U().squareObjects(tile, function(object, index)
                    local label = string.lower(tostring(select(1,
                        U().call(object, "getName")) or ""))
                    local sprite = select(1, U().call(object, "getSprite"))
                    local texture = string.lower(tostring(sprite and select(1,
                        U().call(sprite, "getName")) or ""))
                    if string.find(label, "chair", 1, true)
                        or string.find(texture, "seating", 1, true) then
                        site.chair = { x = position.x, y = position.y,
                            z = position.z or 0, objectIndex = index }
                        return false
                    end
                end, 64)
            end
            if site.chair then break end
        end
        if not site.chair then return nil end
    elseif definition.id == "werewolf_dalton_reese" then
        local bounds = house.bounds or {}
        for x = bounds.x1, bounds.x2 do
            for y = bounds.y1, bounds.y2 do
                local cellarSquare = U().gridSquare(x, y, -1)
                local cellarName = roomName(cellarSquare)
                if cellarSquare and candidateUnseen(cellarSquare,
                    player, allowSeen)
                    and (cellarName == "basement"
                        or cellarName == "cellar"
                        or cellarName == "storage") then
                    site.cellar = point(cellarSquare)
                    U().squareObjects(cellarSquare, function(object, index)
                        if not site.cellarDoor
                            and U().instanceOf(object, "IsoDoor") then
                            site.cellarDoor = { x = x, y = y, z = -1,
                                objectIndex = index, kind = "door" }
                        end
                    end, 64)
                end
                if site.cellar and site.cellarDoor then break end
            end
            if site.cellar and site.cellarDoor then break end
        end
        if not site.cellar or not site.cellarDoor then return nil end
        for radius = 15, 25, 5 do
            for angle = 0, 15 do
                local theta = angle * math.pi / 8
                local treeSquare = U().gridSquare(
                    math.floor(spawn.x + math.cos(theta) * radius),
                    math.floor(spawn.y + math.sin(theta) * radius), 0)
                local tree = treeSquare and select(1,
                    U().call(treeSquare, "getTree"))
                if tree then
                    local tx, ty = U().position(treeSquare)
                    for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
                        { 0, 1 }, { 0, -1 } }) do
                        local target = U().gridSquare(
                            math.floor(tx + offset[1]),
                            math.floor(ty + offset[2]), 0)
                        if candidateUnseen(target, player, allowSeen) then
                            site.woods = point(target); break
                        end
                    end
                end
                if site.woods then break end
            end
            if site.woods then break end
        end
        if not site.woods then return nil end
    end
    if definition.id == "shotgun_farmer_wendell"
        or definition.id == "duchess_hollis_burkett"
        or definition.id == "crabtree_sheep_farm"
        or definition.id == "jedediah_cattle_drive"
        or definition.id == "tommy_two_lengths" then
        site.coop = coopIn(house)
        if site.coop == nil then return nil end
        if definition.id == "shotgun_farmer_wendell" then
            site.truck = nearbyTruck(house)
        elseif site.spawn.x == site.coop.x and site.spawn.y == site.coop.y then
            site.spawn = otherRoomTile(house, site.spawn) or site.spawn
        end
    elseif definition.id == "party_room12_delbert" then
        site.partyDoor = partyOpening(house, spawn, "door")
        site.partyWindow = partyOpening(house, spawn, "window")
        site.coop = otherRoomTile(house, spawn)
        if not site.partyDoor or not site.partyWindow or not site.coop then
            return nil
        end
        site.coop.enclosed = true
    elseif definition.id == "ranger_june_whitlock" then
        site.animalSpawns = rabbitSpawns(house, spawn, player, allowSeen)
        if not site.animalSpawns then return nil end
    end
    if definition.id == "mien_ward" then
        -- He first appears inside a matching shop, then uses the normal
        -- roamer hibernation snapshot rather than occupying a household.
        site.kind = "roamer"
    end
    return site
end

Oddballs._siteForResidentForTests = siteForResident

local function siteForRivals(square, player, definition, allowSeen)
    local site = siteForResident(square, player, definition,
        roomName(square), allowSeen)
    if not site then return nil end
    local origin = site.house.anchor
    local visited = {}
    for radius = 12, 36, 4 do
        for angle = 0, 15 do
            local theta = angle * math.pi / 8
            local candidate = U().gridSquare(
                math.floor(origin.x + math.cos(theta) * radius),
                math.floor(origin.y + math.sin(theta) * radius), 0)
            local building = candidate and select(1,
                U().call(candidate, "getBuilding"))
            if building and not visited[building] then
                visited[building] = true
                local house = SC.Factions.oddballHouseAt(candidate,
                    player, allowSeen)
                if house and house.id ~= site.house.id then
                    for _, position in ipairs(house.interior or {}) do
                        local post = U().gridSquare(position.x, position.y,
                            position.z or 0)
                        if post and candidateUnseen(post, player,
                            allowSeen) then
                            site.rivalSite = { kind = "resident",
                                room = roomName(post), house = house,
                                anchor = point(post), spawn = point(post) }
                            return site
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function siteForVisitors(square, player, allowSeen)
    local name = roomName(square)
    if name ~= "barn" and name ~= "farmstorage" then return nil end
    local house = SC.Factions.oddballHouseAt(square, player, allowSeen)
    if not house then return nil end
    local anchor = house.anchor
    local posts = {}
    for radius = 4, 9 do
        for dx = -radius, radius, 2 do
            for _, dy in ipairs({ -radius, radius }) do
                local candidate = U().gridSquare(anchor.x + dx,
                    anchor.y + dy, 0)
                if candidate and roomName(candidate) == nil
                    and candidateUnseen(candidate, player, allowSeen)
                    and not roadSquare(candidate)
                    and separated(posts, point(candidate), 2) then
                    posts[#posts + 1] = point(candidate)
                    if #posts == 4 then break end
                end
            end
            if #posts == 4 then break end
        end
        if #posts == 4 then break end
    end
    if #posts < 3 then return nil end
    local woods
    for radius = 13, 25, 3 do
        for angle = 0, 15 do
            local theta = angle * math.pi / 8
            local candidate = U().gridSquare(
                math.floor(anchor.x + math.cos(theta) * radius),
                math.floor(anchor.y + math.sin(theta) * radius), 0)
            local tree = candidate and select(1, U().call(candidate,
                "getTree"))
            if candidate and tree and roomName(candidate) == nil
                and candidateUnseen(candidate, player, allowSeen) then
                -- A nearby free square avoids asking navigation to stand in
                -- the tree while still making the walk visibly enter woods.
                local cx, cy = U().position(candidate)
                for _, delta in ipairs({ { 1, 0 }, { -1, 0 },
                    { 0, 1 }, { 0, -1 } }) do
                    local adjacent = U().gridSquare(
                        math.floor(cx + delta[1]),
                        math.floor(cy + delta[2]), 0)
                    if adjacent and candidateUnseen(adjacent, player,
                        allowSeen) then woods = point(adjacent); break end
                end
            end
            if woods then break end
        end
        if woods then break end
    end
    if not woods then return nil end
    local cache
    for _, position in ipairs(house.interior or {}) do
        local interior = U().gridSquare(position.x, position.y,
            position.z or 0)
        if interior and not cache then
            U().squareObjects(interior, function(object, index)
                if cache then return end
                local container = select(1, U().call(object,
                    "getContainer"))
                if container then
                    local kind = select(1, U().call(container, "getType"))
                    cache = { x = position.x, y = position.y,
                        z = position.z or 0, objectIndex = index,
                        containerType = kind }
                end
            end, 64)
        end
        if cache then break end
    end
    if not cache then return nil end
    return { kind = "resident", room = name, house = house,
        anchor = posts[1], spawn = posts[1],
        memberSpawns = { posts[1], posts[2], posts[3], posts[4] },
        woods = woods, cache = cache }
end

local function siteForRed(square, player, allowSeen)
    if not candidateUnseen(square, player, allowSeen) or not roadSquare(square)
        or nearbyZombies(square) < 4 then return nil end
    local house, room = shelterNear(square, player, allowSeen)
    if not house then return nil end
    local start = point(square)
    return { kind = "roamer", room = room, house = house,
        anchor = start, spawn = start }
end

local function siteForEbb(square, player, allowSeen, ignoreClock)
    local hour = worldClockHour()
    if not ignoreClock and (not hour or hour < 18 or hour >= 22) then
        return nil
    end
    if not candidateUnseen(square, player, allowSeen) or not roadSquare(square)
        or roomName(square) ~= nil then return nil end
    local house, room = shelterNear(square, player, allowSeen)
    if not house then return nil end
    local start = point(square)
    return { kind = "roamer", room = room, house = house,
        anchor = start, spawn = start }
end

local function siteForBigChris(square, player, allowSeen)
    local name = roomName(square)
    if name ~= "grocery" and name ~= "gigamart"
        and name ~= "spiffos" and name ~= "clothingstore"
        and name ~= "bar" then return nil end
    local house = SC.Factions.oddballHouseAt(square, player, allowSeen)
    if not house then return nil end
    local anchor = house.anchor
    local bins, seen = {}, {}
    for radius = 3, 27, 3 do
        for angle = 0, 23 do
            local theta = angle * math.pi / 12
            local x = math.floor(anchor.x + math.cos(theta) * radius)
            local y = math.floor(anchor.y + math.sin(theta) * radius)
            local tile = U().gridSquare(x, y, 0)
            if tile and roomName(tile) == nil
                and objectTileUnseen(tile, player, allowSeen)
                and not seen[x .. ":" .. y] then
                seen[x .. ":" .. y] = true
                U().squareObjects(tile, function(object, index)
                    local container = select(1,
                        U().call(object, "getContainer"))
                    local kind = container and select(1,
                        U().call(container, "getType"))
                    kind = string.lower(tostring(kind or ""))
                    if kind == "bin" or kind == "dumpster" then
                        bins[#bins + 1] = { x = x, y = y, z = 0,
                            objectIndex = index, containerType = kind }
                        return false
                    end
                end, 32)
            end
            if #bins >= 6 then break end
        end
        if #bins >= 6 then break end
    end
    if #bins < 2 then return nil end
    local start
    for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
        { 0, 1 }, { 0, -1 } }) do
        local tile = U().gridSquare(bins[1].x + offset[1],
            bins[1].y + offset[2], 0)
        if candidateUnseen(tile, player, allowSeen) then
            start = point(tile); break
        end
    end
    if not start then return nil end
    local rascalPost
    for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
        { 0, 1 }, { 0, -1 } }) do
        local tile = U().gridSquare(bins[2].x + offset[1],
            bins[2].y + offset[2], 0)
        local tx, ty = U().position(tile)
        if candidateUnseen(tile, player, allowSeen)
            and (tx ~= start.x or ty ~= start.y) then
            rascalPost = point(tile); break
        end
    end
    if not rascalPost then return nil end
    return { kind = "roamer", room = name, house = house,
        anchor = start, spawn = start,
        bins = bins, animalSpawns = { rascalPost } }
end

local function siteForFan(square, player, allowSeen)
    if not candidateUnseen(square, player, allowSeen)
        or roomName(square) ~= nil then return nil end
    local house, room = shelterNear(square, player, allowSeen)
    if not house then return nil end
    local start = point(square)
    return { kind = "roamer", room = room, house = house,
        anchor = start, spawn = start }
end

local function siteForKnight(square, player, stage, allowSeen)
    if not candidateUnseen(square, player, allowSeen) then return nil end
    local name = roomName(square)
    local z = select(3, U().position(square))
    if stage == 1 and name ~= "office" then return nil end
    if stage == 2 and name ~= "bedroom" then return nil end
    if stage == 3 and (not z or z >= 0) then return nil end
    if stage == 3 and nearbyZombies(square) < 3 then return nil end
    if stage == 2 and nearbyZombies(square) < 2 then return nil end
    local house = SC.Factions.oddballHouseAt(square, player, allowSeen)
    if not house then return nil end
    if stage == 2 then
        local door = partyOpening(house, point(square), "door")
        if not door then return nil end
        local doorSquare = U().gridSquare(door.x, door.y, door.z or 0)
        local objects = select(1, U().call(doorSquare, "getObjects"))
        local object = objects and SC.NativeList
            and SC.NativeList.get(objects, door.objectIndex) or nil
        local open = select(1, U().call(object, "IsOpen"))
        if not object or open == true then return nil end
    end
    if stage == 1 then
        local station = false
        for _, position in ipairs(house.interior or {}) do
            local candidate = U().gridSquare(position.x, position.y,
                position.z or 0)
            local room = roomName(candidate)
            if room == "gasstation" or room == "gasstore"
                or room == "gasstationstore" then station = true; break end
        end
        if not station then return nil end
    end
    local start = point(square)
    return { kind = "roamer", room = name, house = house,
        anchor = start, spawn = start }
end

local function siteForRoyce(square, player, allowSeen)
    local site = siteForEbb(square, player, allowSeen, true)
    if not site or not site.house then return nil end
    site.stashSpawns = {}
    local interior = site.house.interior or {}
    for index = 1, #interior do
        local position = interior[index]
        local candidate = U().gridSquare(position.x, position.y,
            position.z or 0)
        if candidate and candidateUnseen(candidate, player, allowSeen)
            and (position.x - site.spawn.x) ^ 2
                + (position.y - site.spawn.y) ^ 2 >= 16 then
            site.stashSpawns[#site.stashSpawns + 1] = point(candidate)
            if #site.stashSpawns >= 5 then break end
        end
    end
    if #site.stashSpawns < 3 then return nil end
    site.stashEntry = site.house.primaryEntry
    return site
end

local function siteForMose(square, player, allowSeen)
    local name = roomName(square)
    if name ~= "porch" and name ~= "livingroom" then return nil end
    local house = SC.Factions.oddballHouseAt(square, player, allowSeen)
    if not house or not house.primaryEntry then return nil end
    local door = house.primaryEntry
    local porch
    for dx = -2, 2 do
        for dy = -2, 2 do
            local candidate = U().gridSquare(door.x + dx,
                door.y + dy, 0)
            if candidate and roomName(candidate) == nil
                and candidateUnseen(candidate, player, allowSeen) then
                porch = point(candidate)
                break
            end
        end
        if porch then break end
    end
    if not porch then return nil end
    local trees = 0
    for dx = -8, 8, 2 do
        for dy = -8, 8, 2 do
            local candidate = U().gridSquare(porch.x + dx,
                porch.y + dy, 0)
            local tree = select(1, U().call(candidate, "getTree"))
            if tree then trees = trees + 1 end
        end
    end
    if trees < 4 then return nil end
    return { kind = "resident", room = name, house = house,
        anchor = porch, spawn = porch }
end

function Oddballs.findKnightSite(player, stage, previous)
    if not player or (stage ~= 2 and stage ~= 3) then return nil end
    local px, py = U().position(player)
    if not px then return nil end
    scanSerial = scanSerial + 1
    for index = 1, SAMPLE_BUDGET do
        local angle = index * GOLDEN_ANGLE + scanSerial * 0.37
        local radius = 35 + ((index * 17 + scanSerial * 11) % 85)
        local x = math.floor(px + math.cos(angle) * radius)
        local y = math.floor(py + math.sin(angle) * radius)
        local square = U().gridSquare(x, y, stage == 3 and -1 or 0)
        local site = square and siteForKnight(square, player, stage, false)
        if site and (not previous or site.house.id ~= previous.id) then
            return site
        end
    end
    return nil
end

-- Called only for a zombie whose recorded killer is the local player. A fan
-- can enter at the scene of that real kill, never from a calendar-only scan.
function Oddballs.notePlayerKill(player, zombie)
    local definition = byId.fan_corey_biggs
    if not player or not zombie or not definition then
        return false, "kill_witness_unavailable"
    end
    local seeded = state.seeded[definition.id]
    if seeded then
        local group = SC.Factions and SC.Factions.group(seeded.groupId)
        local owner = SC.OddballCorey
        if group and owner and type(owner.noteKill) == "function" then
            return owner.noteKill(group, player, zombie)
        end
        return false, "fan_no_longer_present"
    end
    if state.pending or state.retired[definition.id]
        or state.disabled == true then return false, "fan_not_available" end
    if (type(isClient) == "function" and isClient() == true)
        or (type(isServer) == "function" and isServer() == true) then
        return false, "single_player_only"
    end
    if not SC.Actor or SC.Actor.checkBridge(false) ~= true then
        return false, "actor_provider_unavailable"
    end
    local px, py, pz = U().position(player)
    if not px or math.floor(pz or 0) ~= 0 then
        return false, "fan_ground_floor_required"
    end
    scanSerial = scanSerial + 1
    for index = 1, 18 do
        local angle = index * GOLDEN_ANGLE + scanSerial * 0.31
        local radius = 12 + (index % 7)
        local square = U().gridSquare(math.floor(px + math.cos(angle) * radius),
            math.floor(py + math.sin(angle) * radius), 0)
        local site = square and siteForFan(square, player, false)
        if site then
            local group, reason = SC.Factions.createOddballGroup(site, definition)
            if group then
                if type(group.oddball) == "table" and SC.OddballCorey
                    and type(SC.OddballCorey.describeKill) == "function" then
                    group.oddball.initialTale =
                        SC.OddballCorey.describeKill(player, zombie)
                end
                state.pending = { id = definition.id, groupId = group.id }
                return true, group.id
            end
            return false, reason or "fan_spawn_failed"
        end
    end
    return false, "no_safe_witness_post"
end

function Oddballs.findRoamerLandmark(player, previous, requireDusk, minSeparation)
    if not player then return nil end
    local px, py, pz = U().position(player)
    if not px or pz ~= 0 then return nil end
    minSeparation = tonumber(minSeparation) or 160
    scanSerial = scanSerial + 1
    for index = 1, SAMPLE_BUDGET do
        local angle = index * GOLDEN_ANGLE + scanSerial * 0.61
        local radius = 35 + ((index * 17 + scanSerial * 11) % 55)
        local x = math.floor(px + math.cos(angle) * radius)
        local y = math.floor(py + math.sin(angle) * radius)
        if not previous or (x - previous.x) ^ 2
            + (y - previous.y) ^ 2 >= minSeparation * minSeparation then
            local square = U().gridSquare(x, y, 0)
            local site = siteForEbb(square, player, false,
                requireDusk ~= true)
            if site then return site end
        end
    end
    return nil
end

function Oddballs.findEbbSite(player, previous)
    return Oddballs.findRoamerLandmark(player, previous, true, 160)
end

local function siteForDefenseLeague(square, player, allowSeen)
    if not candidateUnseen(square, player, allowSeen) or not roadSquare(square)
        or roomName(square) ~= nil then return nil end
    local center = point(square)
    if not center or center.z ~= 0 then return nil end
    local directions = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
    local roads, posts = 0, { center }
    for _, direction in ipairs(directions) do
        local adjacent = U().gridSquare(center.x + direction[1],
            center.y + direction[2], 0)
        if roadSquare(adjacent) then
            roads = roads + 1
            if #posts < 4 and candidateUnseen(adjacent, player, allowSeen) then
                posts[#posts + 1] = point(adjacent)
            end
        end
    end
    -- A three-way road junction gives the four patrol members distinct posts.
    if roads < 3 or #posts < 4 then return nil end
    local house = shelterNear(square, player, allowSeen)
    if not house then return nil end
    return { kind = "roamer", room = "road junction", house = house,
        anchor = center, spawn = center, memberSpawns = posts }
end

local function unresolvedCount()
    local count = 0
    local groups = SC.Factions and type(SC.Factions.list) == "function"
        and SC.Factions.list(false) or {}
    for _, group in ipairs(groups) do
        if type(group.oddball) == "table" and group.lifecycle ~= "destroyed"
            and state.retired[group.oddball.id] == nil then
            count = count + 1
        end
    end
    return count
end

local function configInteger(key, fallback, minimum, maximum)
    local value = tonumber(SC.Config and SC.Config.get(key)) or fallback
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

local function reconcileGroups(candidate)
    local groups = SC.Factions and type(SC.Factions.list) == "function"
        and SC.Factions.list(false) or {}
    for _, group in ipairs(groups) do
        local story = type(group.oddball) == "table" and group.oddball or nil
        if story and byId[story.id] then
            if group.lifecycle == "destroyed" then
                candidate.retired[story.id] = candidate.retired[story.id] or "resolved"
            elseif story.spawned == true or (type(group.members) == "table"
                and group.members[1] and group.members[1].actorId ~= nil) then
                candidate.seeded[story.id] = candidate.seeded[story.id] or {
                    groupId = group.id, day = tonumber(group.createdDay) or 0 }
                candidate.lastSeedDay = math.max(tonumber(candidate.lastSeedDay)
                    or -math.huge, candidate.seeded[story.id].day)
                story.spawned = true
            else
                candidate.pending = { id = story.id, groupId = group.id }
            end
        end
    end
end

function Oddballs.isKnownId(id)
    return byId[id] ~= nil
end

function Oddballs.definition(id)
    return byId[id]
end

function Oddballs.state(group)
    if type(group) ~= "table" or type(group.oddball) ~= "table" then return nil end
    return group.oddball
end

function Oddballs.groupForActor(actor)
    local affiliation = SC.Factions and SC.Factions.affiliation(actor) or nil
    local group = affiliation and affiliation.group or nil
    if group == nil then
        local actorId = U().idOf(actor)
        local origin = actorId and SC.FactionRecruitment
            and type(SC.FactionRecruitment.originForActor) == "function"
            and SC.FactionRecruitment.originForActor(actorId) or nil
        group = origin and origin.group or nil
    end
    return group and type(group.oddball) == "table" and group or nil
end

-- Build 42 forces IsoGameCharacter.setZombiesDontAttack off for any character
-- without a cheat capability, and a companion never has one: the call
-- "succeeds" and changes nothing. The native bridge owns a private, temporary
-- flag for scripted companions instead. Read it back, so a missing or stale
-- bridge is never mistaken for a working shelter.
function Oddballs.setZombieShelter(actor, enabled)
    if actor == nil then return false, "actor_missing" end
    enabled = enabled == true
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if bridge == nil or not SC.Call or type(SC.Call.static) ~= "function" then
        return false, "bridge_unavailable"
    end
    local called, accepted = SC.Call.static(bridge, "setStoryZombieIgnored",
        actor, enabled)
    if not called or accepted ~= true then return false, "bridge_refused" end
    local observed, observedOk = U().call(actor, "isZombiesDontAttack")
    if not observedOk or observed ~= enabled then return false, "shelter_not_applied" end
    return true
end

function Oddballs.isZombieIgnored(actor)
    local group = Oddballs.groupForActor(actor)
    if not group then return false end
    local ignored, reason = callModule(group, "zombiesIgnore", actor, group)
    return ignored == true, reason
end

function Oddballs.avoidsZombieCombat(actor, group)
    group = group or Oddballs.groupForActor(actor)
    if not group then return false end
    local module = moduleFor(group)
    if type(module) == "table" and type(module.avoidsZombieCombat) == "function" then
        local avoids = callModule(group, "avoidsZombieCombat", actor, group)
        return avoids == true
    end
    -- The gore-cloaked roamer keeps the established behavior: he has no
    -- reason to swing at a horde that does not perceive him.
    return Oddballs.isZombieIgnored(actor) == true
end

function Oddballs.intentFor(actor, player, snapshot, group)
    group = group or Oddballs.groupForActor(actor)
    if not group then return nil end
    local intent = callModule(group, "intentFor", actor, player, snapshot, group)
    if type(intent) ~= "table" then return nil end
    intent.kind = "faction"
    intent.factionId = group.id
    intent.priority = tonumber(intent.priority) or 28
    return intent
end

function Oddballs.update(actor, player, runtime, intent, group)
    group = group or Oddballs.groupForActor(actor)
    if not group then return false, "not_an_oddball" end
    if type(intent) ~= "table" or intent.mode == "oddball_idle"
        or intent.mode == "zombie_defense" then
        return false, "oddball_idle"
    end
    local handled, reason = callModule(group, "update", actor, player, runtime, intent, group)
    return handled == true, reason
end

function Oddballs.pulseGroup(group, player, current)
    if type(group) ~= "table" or type(group.oddball) ~= "table" then return false end
    roomGuard("pulse", group, player, current)
    local handled, reason = callModule(group, "pulse", group, player, current)
    if SC.OddballDistressRadio
        and type(SC.OddballDistressRadio.pulse) == "function" then
        SC.OddballDistressRadio.pulse(group, player, current)
    end
    return handled ~= false, reason
end

function Oddballs.onZombieDead(zombie, attacker, player)
    if zombie == nil then return false, "zombie_unavailable" end
    for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        if type(group.oddball) == "table" and group.lifecycle ~= "destroyed" then
            local module = moduleFor(group)
            if type(module) == "table" and type(module.onZombieDead) == "function" then
                callModule(group, "onZombieDead", group, zombie, attacker, player)
            end
        end
    end
    return true
end

function Oddballs.onCharacterDeath(actor)
    local seeded = state.seeded.milli_tea_and_trouble
    if not actor or not seeded or not SC.OddballMilli then return false end
    local group = SC.Factions and SC.Factions.group(seeded.groupId)
    if not group or not group.oddball
        or group.oddball.id ~= "milli_tea_and_trouble" then return false end
    if U().instanceOf(actor, "IsoAnimal") then
        local data = U().modData(actor)
        local slot = data and tonumber(data.lfOddballAnimalSlot)
        if data and data.lfOddballGroupId == group.id
            and (slot == 1 or slot == 2)
            and type(SC.OddballMilli.onAnimalDeath) == "function" then
            local attacker = select(1, U().call(actor, "getAttackedBy"))
            return callModule(group, "onAnimalDeath", actor, attacker) == true
        end
        return false
    end
    if not U().instanceOf(actor, "IsoZombie")
        and type(SC.OddballMilli.onKeeperDeath) == "function" then
        -- The native death callback may run after registry affiliation is
        -- cleared. Milli verifies the actor against her persistent member ID.
        return callModule(group, "onKeeperDeath", actor, group) == true
    end
    return false
end

function Oddballs.noteChallengeKill(actor, zombie)
    if not actor or not zombie then return false end
    local seeded = state.seeded.cameraman_skeeter_bowles
    local group = seeded and SC.Factions
        and SC.Factions.group(seeded.groupId) or nil
    if not group or group.lifecycle == "destroyed" or not SC.OddballSkeeter
        or type(SC.OddballSkeeter.noteKill) ~= "function" then
        return false
    end
    return SC.OddballSkeeter.noteKill(group, actor, zombie)
end

function Oddballs.storyAction(groupId, action, player, payload)
    local group = SC.Factions and SC.Factions.group(groupId) or nil
    if not group or type(group.oddball) ~= "table" then
        return false, "oddball_unavailable"
    end
    local accepted, reason = callModule(group, "action", group, action, player, payload)
    return accepted == true, reason
end

function Oddballs.sealedDoorGroup(object, player)
    local behavior = SC.OddballSurvivalist
    if not object or not player or type(behavior) ~= "table"
        or type(behavior.matchesDoor) ~= "function" then return nil end
    for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        if group.oddball and group.oddball.id == "survivalist_locked_horde" then
            local okay, matched = pcall(behavior.matchesDoor, group, object, player)
            if okay and matched == true then return group end
        end
    end
    return nil
end

function Oddballs.menuOptions(group, player)
    if type(group) ~= "table" or type(group.oddball) ~= "table" then return {} end
    local options = callModule(group, "menuOptions", group, player)
    return type(options) == "table" and options or {}
end

function Oddballs.canRecruit(group)
    if type(group) ~= "table" or type(group.oddball) ~= "table" then return false end
    local allowed = callModule(group, "canRecruit", group)
    return allowed == true
end

local function seedPersonalKit(group, actor)
    local story = group and group.oddball
    -- Milli's scene module chooses between horse and bottle variants and
    -- seeds exact quantities; the generic kit deduplicates repeated types.
    if story and story.id == "milli_tea_and_trouble" then
        return true, "milli_module_kit"
    end
    local definition = story and byId[story.id]
    local kit = definition and definition.kit
    if not kit or story.kitSeeded == true then return true, "kit_already_ready" end
    if type(group.members) == "table" and #group.members > 1 then
        local first = group.members[1]
        local actorId = actor and U().idOf(actor)
        if not first or actorId == nil or first.actorId ~= actorId then
            return true, "kit_reserved_for_first_member"
        end
    end
    local inventory = actor and U().inventory(actor)
    if not inventory then return false, "kit_inventory_unavailable" end
    local present = {}
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 200, 8)) do
        local kind = U().itemType(item)
        if kind then present[kind] = present[kind] or item end
    end
    local function ensure(kind)
        if present[kind] then return present[kind] end
        local item = U().addItem(inventory, kind)
        if item then present[kind] = item end
        return item
    end
    local weapon = kit.weapon and ensure(kit.weapon) or nil
    if kit.weapon and not weapon then return false, "kit_weapon_unavailable" end
    for _, kind in ipairs(kit.items or {}) do
        if not ensure(kind) then return false, "kit_item_unavailable:" .. kind end
    end
    if weapon and kit.equipWeapon ~= false then
        local accepted, called = U().call(actor, "setPrimaryHandItem", weapon)
        if not called or accepted == false then
            return false, "kit_weapon_equip_failed"
        end
    end
    story.kitSeeded = true
    return true, "kit_ready"
end
Oddballs._seedPersonalKitForTests = seedPersonalKit

function Oddballs.spawned(group, actor)
    local story = Oddballs.state(group)
    if not story or not byId[story.id] then return false, "unknown_oddball" end
    local day = worldDay()
    if state.seeded[story.id] == nil then
        state.seeded[story.id] = { day = day, groupId = group.id }
        state.lastSeedDay = day
    end
    if state.pending and state.pending.groupId == group.id then state.pending = nil end
    story.spawned = true
    roomGuard("register", group, nil, U().nowMs())
    if actor ~= nil then
        local equipped, reason = seedPersonalKit(group, actor)
        if not equipped and SC.Diagnostics
            and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("oddballs", group.id,
                "personal kit unavailable", tostring(reason))
        end
        callModule(group, "onSpawn", group, actor)
    end
    return true, story.id
end

function Oddballs.spawnFailed(group, reason)
    local story = Oddballs.state(group)
    if not story then return false end
    roomGuard("abort", group.id)
    if state.pending and state.pending.groupId == group.id then state.pending = nil end
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("oddballs", group.id,
            "encounter spawn failed without consuming unique seed", tostring(reason))
    end
    return true
end

function Oddballs.retire(group, reason)
    local story = Oddballs.state(group)
    if not story then return false, "not_an_oddball" end
    roomGuard("release", group.id)
    state.retired[story.id] = tostring(reason or "resolved")
    if state.pending and state.pending.groupId == group.id then state.pending = nil end
    if story.id == "milli_tea_and_trouble" and story.keeperDead == true then
        story.stage = "orphaned"
    else
        story.stage = tostring(reason or "resolved")
    end
    return true
end

local function createAuthoredGroup(site, definition, debugCreated)
    if definition.id == "sleeping_it_off" then
        local hash = U().stableHash and U().stableHash(
            tostring(site.house and site.house.id or site.spawn.x)
                .. ":sleeping-dancer") or 0
        local variant = U().copyShallow(definition)
        variant.identity = hash % 2 == 0 and {
            forename = "Darla Jo", surname = "Simms", gender = "female",
            outfit = "StripperPink", visualSeed = 3100212,
        } or {
            forename = "Kenny", surname = "Hoskins", gender = "male",
            outfit = "FiremanStripper", visualSeed = 3100213,
        }
        definition = variant
    end
    local group, reason = SC.Factions.createOddballGroup(
        site, definition, debugCreated)
    if not group then return nil, reason end
    if definition.kind == "rival_pair" then
        local rivalDefinition = byId.bluegrass_bolt
        local rival, rivalReason
        if site.rivalSite and rivalDefinition then
            rival, rivalReason = SC.Factions.createOddballGroup(
                site.rivalSite, rivalDefinition, debugCreated)
        else
            rivalReason = "rival_site_unavailable"
        end
        if rival then
            group.oddball.rivalGroupId = rival.id
            rival.oddball.rivalGroupId = group.id
        else
            group.oddball.rivalSpawnProblem = rivalReason
            if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                SC.Diagnostics.report("oddballs", definition.id,
                    "paired rival spawn deferred", tostring(rivalReason))
            end
        end
    end
    return group
end

function Oddballs.pulse(player, current)
    current = tonumber(current) or U().nowMs()
    if current >= nextRecruitedPulseAt then
        nextRecruitedPulseAt = current + 1000
        for _, group in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
            local story = type(group.oddball) == "table" and group.oddball or nil
            local joinedId = story
                and type(group.recruitment) == "table"
                and group.recruitment.joinedActorId or nil
            -- Milli's verified death can hand her existing native babies to a
            -- recruited friend. Never keep the dead joined actor active.
            if story and story.id == "milli_tea_and_trouble"
                and story.keeperDead == true then
                joinedId = story.caregiverActorId
            end
            local record = joinedId and SC.Registry and SC.Registry.byId(joinedId) or nil
            if record and record.actor and record.recruited == true then
                callModule(group, "pulseRecruited", group, record.actor, player, current)
            end
        end
    end
    if current < nextScanAt then return false, "oddball_scan_throttled" end
    nextScanAt = current + configInteger("oddballScanIntervalMs",
        SCAN_INTERVAL_MS, 1000, 300000)
    if state.disabled then return false, "oddball_state_quarantined" end
    if SC.Config and SC.Config.get("oddballsEnabled") == false then
        return false, "oddballs_disabled"
    end
    if (type(isClient) == "function" and isClient() == true)
        or (type(isServer) == "function" and isServer() == true) then
        return false, "single_player_only"
    end
    if player == nil or not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready = SC.Actor.checkBridge(false)
    if ready ~= true then return false, "actor_provider_unavailable" end
    local currentDay = worldDay()
    local firstDay = configInteger("oddballFirstEligibleDay", 2, 0, 365)
    if currentDay < firstDay then
        return false, "first_day_not_reached"
    end
    if state.pending ~= nil then
        local group = SC.Factions and SC.Factions.group(state.pending.groupId) or nil
        local member = group and group.members and group.members[1] or nil
        local record = member and member.actorId and SC.Registry
            and SC.Registry.byId(member.actorId) or nil
        if group and type(group.oddball) == "table"
            and (group.oddball.spawned == true or record and record.actor) then
            Oddballs.spawned(group, record and record.actor or nil)
        elseif group == nil then
            state.pending = nil
        else
            return false, "oddball_spawn_pending"
        end
    end
    local freeSlots = configInteger("oddballMaxActive",
        MAX_UNRESOLVED, 0, MAX_UNRESOLVED) - unresolvedCount()
    if freeSlots <= 0 then
        return false, "oddball_cap_reached"
    end
    local cooldown = tonumber(SC.Config and SC.Config.get("oddballEncounterDays")) or 3
    if state.lastSeedDay ~= nil and currentDay - state.lastSeedDay < cooldown then
        return false, "oddball_cooldown"
    end
    local px, py, pz = U().position(player)
    if px == nil then return false, "player_position_unavailable" end
    local minimum = configInteger("factionSpawnMinDistance", MIN_DISTANCE, 1, 1000)
    local maximum = configInteger("factionSpawnMaxDistance", MAX_DISTANCE,
        minimum, 1000)
    local budget = configInteger("oddballScanSampleBudget",
        SAMPLE_BUDGET, 1, SAMPLE_BUDGET)
    local visitedBuildings = {}
    scanSerial = scanSerial + 1
    -- A car encounter has no room tile for the building sampler to discover.
    -- Try its one bounded loaded-vehicle scan periodically, after the same
    -- global cap/cooldown checks as every other Strange Folk encounter.
    local carDefinition = byId.loretta_ten_and_two
    if carDefinition and state.seeded[carDefinition.id] == nil
        and state.retired[carDefinition.id] == nil
        and currentDay >= firstDay + (carDefinition.firstEligibleOffsetDays or 0)
        and scanSerial % 4 == 0 and SC.OddballLoretta
        and type(SC.OddballLoretta.siteFor) == "function" then
        local site = SC.OddballLoretta.siteFor(player, false, minimum, maximum)
        if site then
            local group, reason = createAuthoredGroup(site, carDefinition)
            if group then
                state.pending = { id = carDefinition.id, groupId = group.id }
                return true, group.id
            end
            if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                SC.Diagnostics.report("oddballs", carDefinition.id,
                    "vehicle candidate deferred", tostring(reason))
            end
        end
    end
    for index = 1, budget do
        local angle = index * GOLDEN_ANGLE + scanSerial * 0.61
        local distance = minimum + ((index * 17 + scanSerial * 11)
            % (maximum - minimum + 1))
        local x = math.floor(px + math.cos(angle) * distance)
        local y = math.floor(py + math.sin(angle) * distance)
        -- One rotated neighborhood point per ring anchor keeps the entire
        -- pass at 96 loaded-square probes while covering nearby landmarks
        -- across successive pulses.
        local offset = SEARCH_OFFSETS[((index + scanSerial * 3 - 1)
            % #SEARCH_OFFSETS) + 1]
            local cx, cy = x + offset[1], y + offset[2]
            local dx, dy = cx - px, cy - py
            local rangeSq = dx * dx + dy * dy
            if rangeSq >= minimum * minimum and rangeSq <= maximum * maximum then
                local square = U().gridSquare(cx, cy, math.floor(pz or 0))
                if square and not U().canSee(player, square) then
                    local name = roomName(square)
                    local building = name and select(1, U().call(square, "getBuilding"))
                    for _, definition in ipairs(definitions) do
                        if state.seeded[definition.id] == nil
                            and state.retired[definition.id] == nil
                            and (definition.kind ~= "rival_pair" or freeSlots >= 2)
                            and currentDay >= firstDay
                                + (definition.firstEligibleOffsetDays or 0) then
                            local site
                            if definition.kind == "patrol" then
                                site = siteForDefenseLeague(square, player)
                            elseif definition.kind == "knight" then
                                site = siteForKnight(square, player, 1, false)
                            elseif definition.kind == "trickster" then
                                site = siteForRoyce(square, player, false)
                            elseif definition.kind == "mose" then
                                site = siteForMose(square, player, false)
                            elseif definition.kind == "visitors" then
                                site = siteForVisitors(square, player, false)
                            elseif definition.kind == "rival_pair" then
                                site = siteForRivals(square, player,
                                    definition, false)
                            elseif definition.kind == "challenge" then
                                site = siteForEbb(square, player, false, true)
                            elseif definition.kind == "trash_runner" then
                                site = siteForBigChris(square, player, false)
                            elseif definition.kind == "forest_camp"
                                and SC.OddballCampStoryteller
                                and type(SC.OddballCampStoryteller.siteFor)
                                    == "function" then
                                site = SC.OddballCampStoryteller.siteFor(
                                    square, player, false)
                            elseif definition.kind == "roamer" then
                                if definition.id == "peddler_mister_ebb" then
                                    site = siteForEbb(square, player)
                                elseif definition.id == "dewey_prentice_hollowell" then
                                    site = siteForEbb(square, player, false, true)
                                else
                                    site = siteForRed(square, player)
                                end
                            elseif isResidentRoom(definition.id, name) and building
                                and not (visitedBuildings[definition.id]
                                    and visitedBuildings[definition.id][building]) then
                                visitedBuildings[definition.id] =
                                    visitedBuildings[definition.id] or {}
                                visitedBuildings[definition.id][building] = true
                                site = siteForResident(square, player,
                                    definition, name)
                            end
                            if site then
                                local group, reason = createAuthoredGroup(
                                    site, definition)
                                if group then
                                    state.pending = { id = definition.id,
                                        groupId = group.id }
                                    return true, group.id
                                end
                                if SC.Diagnostics
                                    and type(SC.Diagnostics.report) == "function" then
                                    SC.Diagnostics.report("oddballs", definition.id,
                                        "candidate site deferred", tostring(reason))
                                end
                            end
                        end
                    end
                end
            end
    end
    return false, "no_eligible_loaded_site"
end

-- A private playtest control: skip the calendar and encounter cap, but still
-- place an unused character at a real, safe landmark. It never clears the
-- unique ledger, so clicking repeatedly cannot duplicate a character.
function Oddballs.debugSpawnRandom(player)
    if not SC.Config or SC.Config.get("debugSpawnEnabled") ~= true then
        return false, "debug_tools_disabled"
    end
    if state.disabled then return false, "oddball_state_quarantined" end
    if (type(isClient) == "function" and isClient() == true)
        or (type(isServer) == "function" and isServer() == true) then
        return false, "single_player_only"
    end
    if not player or not SC.Actor or type(SC.Actor.checkBridge) ~= "function" then
        return false, "actor_provider_unavailable"
    end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then
        return false, providerReason or "actor_provider_unavailable"
    end
    if state.pending ~= nil then return false, "oddball_spawn_pending" end
    local available = 0
    for _, definition in ipairs(definitions) do
        if state.seeded[definition.id] == nil
            and state.retired[definition.id] == nil then
            available = available + 1
        end
    end
    if available == 0 then return false, "all_strange_folk_used" end
    local px, py, pz = U().position(player)
    if px == nil then return false, "player_position_unavailable" end

    local candidates, found, visitedBuildings = {}, {}, {}
    local minimum, maximum, budget = 8, 55, 160
    scanSerial = scanSerial + 1
    local carDefinition = byId.loretta_ten_and_two
    if carDefinition and state.seeded[carDefinition.id] == nil
        and state.retired[carDefinition.id] == nil and SC.OddballLoretta
        and type(SC.OddballLoretta.siteFor) == "function" then
        local site = SC.OddballLoretta.siteFor(player, true, minimum, maximum)
        if site then
            found[carDefinition.id] = true
            candidates[#candidates + 1] = {
                definition = carDefinition, site = site }
        end
    end
    for index = 1, budget do
        local angle = index * GOLDEN_ANGLE + scanSerial * 0.61
        local distance = minimum + ((index * 17 + scanSerial * 11)
            % (maximum - minimum + 1))
        local offset = SEARCH_OFFSETS[((index + scanSerial * 3 - 1)
            % #SEARCH_OFFSETS) + 1]
        local x = math.floor(px + math.cos(angle) * distance) + offset[1]
        local y = math.floor(py + math.sin(angle) * distance) + offset[2]
        local dx, dy = x - px, y - py
        local rangeSq = dx * dx + dy * dy
        if rangeSq >= minimum * minimum and rangeSq <= maximum * maximum then
            local square = U().gridSquare(x, y, math.floor(pz or 0))
            if square then
                local name = roomName(square)
                local building = name and select(1, U().call(square, "getBuilding"))
                for _, definition in ipairs(definitions) do
                    if not found[definition.id]
                        and state.seeded[definition.id] == nil
                        and state.retired[definition.id] == nil then
                        local site
                        if definition.kind == "patrol" then
                            site = siteForDefenseLeague(square, player, true)
                        elseif definition.kind == "knight" then
                            site = siteForKnight(square, player, 1, true)
                        elseif definition.kind == "trickster" then
                            site = siteForRoyce(square, player, true)
                        elseif definition.kind == "mose" then
                            site = siteForMose(square, player, true)
                        elseif definition.kind == "visitors" then
                            site = siteForVisitors(square, player, true)
                        elseif definition.kind == "rival_pair" then
                            site = siteForRivals(square, player,
                                definition, true)
                        elseif definition.kind == "challenge" then
                            site = siteForEbb(square, player, true, true)
                        elseif definition.kind == "trash_runner" then
                            site = siteForBigChris(square, player, true)
                        elseif definition.kind == "forest_camp"
                            and SC.OddballCampStoryteller
                            and type(SC.OddballCampStoryteller.siteFor)
                                == "function" then
                            site = SC.OddballCampStoryteller.siteFor(
                                square, player, true)
                        elseif definition.kind == "witness" then
                            site = siteForFan(square, player, true)
                        elseif definition.kind == "roamer" then
                            if definition.id == "peddler_mister_ebb"
                                or definition.id == "dewey_prentice_hollowell" then
                                site = siteForEbb(square, player, true, true)
                            else
                                site = siteForRed(square, player, true)
                            end
                        elseif isResidentRoom(definition.id, name) and building then
                            visitedBuildings[definition.id] =
                                visitedBuildings[definition.id] or {}
                            if not visitedBuildings[definition.id][building] then
                                visitedBuildings[definition.id][building] = true
                                site = siteForResident(square, player,
                                    definition, name, true)
                            end
                        end
                        if site then
                            found[definition.id] = true
                            candidates[#candidates + 1] = {
                                definition = definition, site = site }
                        end
                    end
                end
                if #candidates >= available then break end
            end
        end
    end
    if #candidates == 0 then return false, "no_eligible_loaded_site" end
    local randomIndex = type(ZombRand) == "function"
        and ZombRand(#candidates) + 1 or math.random(#candidates)
    local choice = candidates[randomIndex]
    local group, reason = createAuthoredGroup(
        choice.site, choice.definition, true)
    if not group then return false, reason or "oddball_spawn_failed" end
    state.pending = { id = choice.definition.id, groupId = group.id }
    return true, group.id
end

function Oddballs.export()
    local copy, reason = SC.StableValue.copyStrict(state, {
        maxDepth = 6, maxEntries = 1024, path = "$.oddballs" })
    if copy == nil then return nil, reason end
    copy.disabled = nil
    return copy
end

function Oddballs.restore(document)
    local candidate = freshState()
    if document ~= nil then
        if type(document) ~= "table" or document.version ~= VERSION
            or type(document.seeded) ~= "table"
            or type(document.retired) ~= "table" then
            state.disabled = true
            return false, "invalid_oddball_state"
        end
        local copy, reason = SC.StableValue.copyStrict(document, {
            maxDepth = 6, maxEntries = 1024, path = "$.oddballs" })
        if copy == nil then
            state.disabled = true
            return false, reason
        end
        if copy.lastSeedDay ~= nil and (type(copy.lastSeedDay) ~= "number"
            or copy.lastSeedDay ~= copy.lastSeedDay
            or copy.lastSeedDay == math.huge or copy.lastSeedDay == -math.huge) then
            state.disabled = true
            return false, "invalid_oddball_last_seed_day"
        end
        local seededCount, retiredCount = 0, 0
        for id, entry in pairs(copy.seeded) do
            seededCount = seededCount + 1
            if not byId[id] or type(entry) ~= "table"
                or type(entry.groupId) ~= "string"
                or type(entry.day) ~= "number" then
                state.disabled = true
                return false, "invalid_oddball_seeded_record"
            end
        end
        for id, reasonText in pairs(copy.retired) do
            retiredCount = retiredCount + 1
            if not byId[id] or type(reasonText) ~= "string" then
                state.disabled = true
                return false, "invalid_oddball_retired_record"
            end
        end
        if seededCount > #definitions or retiredCount > #definitions then
            state.disabled = true
            return false, "oddball_state_exceeds_character_count"
        end
        if copy.pending ~= nil and (type(copy.pending) ~= "table"
            or not byId[copy.pending.id]
            or type(copy.pending.groupId) ~= "string") then
            state.disabled = true
            return false, "invalid_oddball_pending_record"
        end
        candidate = copy
    end
    reconcileGroups(candidate)
    roomGuard("reset")
    candidate.disabled = nil
    state = candidate
    nextScanAt, nextRecruitedPulseAt, scanSerial = 0, 0, 0
    return true
end

function Oddballs.reset()
    roomGuard("reset")
    if SC.OddballSurvivalist
        and type(SC.OddballSurvivalist.remove) == "function" then
        SC.OddballSurvivalist.remove()
    end
    state = freshState()
    nextScanAt, nextRecruitedPulseAt, scanSerial = 0, 0, 0
    return true
end

return Oddballs
