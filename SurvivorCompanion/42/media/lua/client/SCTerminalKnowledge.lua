-- SPDX-License-Identifier: MIT
-- Original stock-setting summaries and unverified fictional outbreak accounts.
-- Only dated local references: no world scans, networking or executable input.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalKnowledge = {}
local K = SC.TerminalKnowledge
K.CATEGORIES = {
    {id="emma",label="EMMA and this computer"}, {id="county",label="County records"},
    {id="event",label="The Knox Event"}, {id="places",label="Towns and landmarks"},
    {id="broadcasts",label="Radio and television"}, {id="local",label="Life in Knox Country"},
    {id="operations",label="Using your camp station"},
    {id="fragments",label="Outbreak fragments"},
}
K.ENTRIES = {}
local function entry(id, category, title, aliases, text, date, related, source)
    K.ENTRIES[#K.ENTRIES+1] = { id=id,category=category,title=title,aliases=aliases,text=text,
        date=date or "1993-01-01",related=related or {},source=source or (category=="operations"
            and "EMMA operating notes" or date and "Archived incident summary" or "Local reference directory") }
end

entry("knox_overview","event","The Knox Event",{"knox event","outbreak","what happened","knox infection"},
    "The Knox Event dates from 6 July 1993. An exclusion zone, disrupted communications and official assurances appear in the early record. Accounts of illness and violence do not supply a verified explanation of its origin. A name for the disaster is easier to obtain than an explanation. This file is background, not a report on the people outside your door.","1993-07-09",{"knox_exclusion","knox_phones","knox_cause"})
entry("knox_exclusion","event","The exclusion zone",{"exclusion zone","quarantine","roadblocks","quarantine zone","military","army"},
    "The military perimeter was presented as a means of containing the emergency. To families inside it, a boundary also meant blocked journeys, unanswered questions and people left on opposite sides. A checkpoint recorded in a broadcast is not a current safe exit. I cannot certify any gate, guard or road from this archive.","1993-07-09",{"knox_phones","knox_mcgrew","knox_overview"})
entry("knox_phones","event","The telephone failures",{"telephone failures","phone lines","communications blackout","knox telecommunications"},
    "Early broadcasts discuss communication failures and Knox Telecommunications. People outside the affected area struggle to reach those inside it. Explanations and promises of restored service do not establish what caused the outbreak. An unanswered telephone is a missing contact, not proof of what happened to its owner.","1993-07-09",{"knox_exclusion","county_contacts","knox_cause"})
entry("knox_mcgrew","event","General John McGrew",{"general mcgrew","john mcgrew","mcgrew"},
    "General John McGrew is a prominent voice in the official response. His reassurances belong beside the changing reports from journalists and witnesses, rather than above them. Statements made by an authority are evidence of that authority's position. They do not settle every question about conditions inside the perimeter.","1993-07-14",{"knox_exclusion","knox_louisville","press_herald"})
entry("knox_cause","event","What caused it?",{"infection origin","outbreak origin","cause of the outbreak","where did it come from","how did it start"},
    "The origin of the Knox Infection is not established by a definitive account. Reports, rumours and locations that look suspicious are different kinds of evidence. A convincing theory still needs a reliable chain between its claims. I will not turn a burger advertisement, a laboratory door or an unpleasant smell into a solved case.","1993-07-09",{"knox_smell","knox_burgers","knox_facility"})
entry("knox_smell","event","Reports of a strange smell",{"strange smell","bad smell","the smell","smell theory"},
    "Some callers refer to an unpleasant smell before the emergency. That establishes that the smell was reported. It does not identify a substance, a source or a transmission route. Several frightened people repeating a detail can make it important to investigate without making one explanation correct.","1993-07-09",{"knox_cause","knox_phones","knox_facility"})
entry("knox_burgers","event","The burger theory",{"spiffo conspiracy","burger theory","infected burgers","spiffo caused it"},
    "The suggestion that a burger chain explains the infection is a theory, not a confirmed finding. Spiffo's is a familiar part of local life; familiarity makes an easy target for suspicion. This archive has no verified evidence that its food caused the Knox Event. A useful suspect and a convenient mascot are not the same thing.","1993-07-09",{"local_spiffo","knox_cause","knox_smell"})
entry("knox_facility","event","The facility theories",{"secret base","military base","secret laboratory","laboratory theory","fort knox"},
    "Restricted sites and research buildings invite questions, especially when official answers are scarce. Their existence is not proof that the infection began there. A uniform, a locked door or laboratory equipment cannot establish that connection on its own. I have no verified research log explaining the origin, and no reason to label an unknown site a cure depot.","1993-07-09",{"knox_cause","knox_mcgrew","knox_exclusion"})
entry("knox_louisville","event","Later reports from Louisville",{"louisville outbreak","louisville reports","perimeter breach"},
    "Later news coverage no longer treats the perimeter as a complete answer to the crisis. Reports from Louisville and around the boundary describe a deteriorating situation. These are dated accounts of the wider event, not a map of your present save. I cannot tell you which street is passable or whether a particular resident escaped.","1993-07-17",{"knox_spread","knox_mcgrew","place_louisville"})
entry("knox_spread","event","Reports beyond Kentucky",{"global outbreak","worldwide outbreak","rest of the world","outside kentucky","second wave"},
    "Later broadcasts report illness beyond the original area and a crisis reaching far beyond Kentucky. They also address people who seem unaffected by a wider wave. None of that gives this terminal a current view of another city. I cannot verify a safe country, an operating airport or a rescue organisation from a local record.","1993-07-18",{"knox_immunity","knox_cause","knox_louisville"})
entry("knox_immunity","event","The immunity reports",{"immunity reports","airborne infection","immune survivors","second infection"},
    "Late broadcasts distinguish those who remain unaffected by the wider infection from protection against a bite. That distinction is not a diagnosis of you or a companion. Your actual injuries and the world's rules still matter. This archive supplies no cure, no laboratory test and no promise that an apparently healthy person is safe.","1993-07-18",{"knox_spread","knox_cause","knox_overview"})

entry("place_muldraugh","places","Muldraugh",{"muldraugh"},
    "Muldraugh is one of Knox Country's principal towns: homes, shops, service businesses and industrial premises along a busy road corridor. Its ordinary buildings explain much of what people left behind. A warehouse on a directory is a possible place to search, not a guarantee of tools, supplies or an empty yard.",nil,{"place_westpoint","local_fossoil","place_rosewood"})
entry("place_westpoint","places","West Point",{"west point","westpoint"},
    "West Point combines a compact commercial centre with surrounding homes and roads toward the river and the wider county. Its shopfronts belonged to people before they became destinations on a scavenging list. I can describe the town's identity. I cannot count its current inhabitants or promise that a route through it is clear.",nil,{"place_muldraugh","place_louisville","place_riverside"})
entry("place_riverside","places","Riverside",{"riverside"},
    "Riverside's riverfront, shops and residential districts give it a different shape from the county's road and warehouse towns. Leisure facilities tell you what the town expected an ordinary summer to look like. They do not tell you whether water is safe to drink or whether the houses have already been searched.",nil,{"place_westpoint","local_spiffo","county_water"})
entry("place_rosewood","places","Rosewood",{"rosewood"},
    "Rosewood has a civic and residential centre, including the services a small town expected to rely on in an emergency. The nearby prison is a separate, much larger institution. A fire station or police station is a location on the map, not evidence that its staff are still there waiting to help.",nil,{"place_prison","place_marchridge","place_muldraugh"})
entry("place_marchridge","places","March Ridge",{"march ridge","marchridge"},
    "March Ridge has dense residential streets and shared community buildings. Its many rooms are reminders of how many separate households an evacuation notice had to reach. A large residential building may contain many doors and few straightforward exits. I have no live occupancy record for any of them.",nil,{"place_rosewood","county_shelter","county_family"})
entry("place_louisville","places","Louisville",{"louisville"},
    "Louisville is the region's large urban centre, with industry, hospitals, shopping, offices and a great many homes. A city contains many different conditions at once. A directory cannot reduce it to safe or unsafe, and a hospital name cannot promise treatment. Ask a returning expedition what it actually observed before choosing a route.",nil,{"place_valley","place_grandohio","knox_louisville"})
entry("place_valley","places","Valley Station",{"valley station"},
    "Valley Station sits among the roads, homes and commercial premises south of Louisville's main urban area. Routes on the city approach connect places that may now have very different conditions. This reference does not identify a cleared approach, an open checkpoint or an operating fuel stop.",nil,{"place_louisville","place_westpoint","county_road"})
entry("place_grandohio","places","The Grand Ohio Mall",{"grand ohio mall","grand ohio"},
    "The Grand Ohio Mall belongs to Louisville's landscape of large commercial developments: many shops gathered into one destination. Advertising made that sound convenient. During an emergency, the same layout also means shared entrances, long internal routes and many unknown rooms. I cannot confirm which shops retain stock.",nil,{"place_louisville","place_crossroads","local_gigamart"})
entry("place_crossroads","places","Crossroads Mall",{"crossroads mall","crossroads"},
    "Crossroads Mall is another major shopping destination in Knox Country. Its name describes a place people once met, worked and spent their weekends. A mall directory is not a manifest of supplies left today. Check exits and agree a meeting point before a group spreads through a building with many departments.",nil,{"place_grandohio","county_shelter","local_gigamart"})
entry("place_prison","places","The prison near Rosewood",{"rosewood prison","knox penitentiary","the prison"},
    "The prison near Rosewood was built to control movement through gates, corridors and secured areas. That makes it a distinctive local institution, not a ready-made safe home. Walls intended to keep people in can be inconvenient when you need everyone out. This terminal has no current roster or working security feed from the site.",nil,{"place_rosewood","knox_exclusion","county_shelter"})

entry("radio_lbmw","broadcasts","LBMW - Kentucky Radio",{"lbmw","kentucky radio"},
    "LBMW is a Kentucky radio broadcaster, listed at 93.2 MHz in the local broadcast directory. Its material mixes local voices, ordinary programming and coverage of the emergency. That number identifies a station; it does not certify that a signal is reaching your radio now. A recording and a live transmission can sound equally confident.",nil,{"radio_nnr","radio_knoxtalk","radio_static"})
entry("radio_nnr","broadcasts","NNR Radio",{"nnr","nnr radio"},
    "NNR Radio is listed at 98.0 MHz. News coverage gives a different perspective from a local caller or official statement, but it is still dated information. Compare when something was reported, where the reporter was and whether an observation was actually confirmed. This file does not tune a receiver or fetch today's bulletin.",nil,{"radio_lbmw","tv_triplen","press_herald"})
entry("radio_knoxtalk","broadcasts","KnoxTalk Radio",{"knoxtalk","knox talk"},
    "KnoxTalk is the talk-radio station listed at 101.2 MHz. Callers' experiences, suspicions and arguments are part of the record of the crisis. They can be valuable without all being correct. A telephone voice may tell you what happened on one road; it cannot, by itself, explain what happened to the whole country.",nil,{"knox_smell","knox_cause","radio_lbmw"})
entry("radio_hitz","broadcasts","Hitz FM",{"hitz fm","hitz"},
    "Hitz FM is listed at 89.4 MHz. Entertainment broadcasting and advertising are part of the world the emergency interrupted. Ordinary programmes continuing beside extraordinary reports can sound absurd. They also show how long a schedule can outlive the circumstances in which it was written.",nil,{"tv_paws","local_spiffo","radio_static"})
entry("tv_triplen","broadcasts","Triple-N",{"triple n","triplen"},
    "Triple-N is a television news channel. Its coverage belongs beside local radio, other television news and dated newspapers when reconstructing the Knox Event. Different reports can reveal changing knowledge rather than one tidy story. This terminal has archived background, not a television aerial disguised as a keyboard.",nil,{"tv_wbln","radio_nnr","knox_overview"})
entry("tv_wbln","broadcasts","WBLN News",{"wbln","wbln news"},
    "WBLN News is another television news source in the local directory. Broadcasts contain announcements, interviews and accounts that change as the emergency develops. Keep the date attached to the information. An early assurance should not be silently relabelled as the last word on an event.",nil,{"tv_triplen","knox_mcgrew","county_notices"})
entry("tv_living","broadcasts","Life and Living TV",{"life and living","life living","life and living tv"},
    "Life and Living carries practical programmes, including cooking, Woodcraft and Exposure Survival. It is a useful record of the skills everyday life relied on before the emergency. Whether a particular programme or recording can still teach you something depends on what you have already learned and the world's rules. I cannot promise a broadcast is on now.",nil,{"tv_woodcraft","tv_exposure","local_video"})
entry("tv_woodcraft","broadcasts","Woodcraft",{"woodcraft"},
    "Woodcraft turns carpentry into television: materials, tools and a project that goes rather better than most first attempts. Its practical instruction is distinct from the adverts around it. EMMA can point you to the programme; she does not award experience by describing an episode or replace the tools needed to do the work.",nil,{"tv_living","ops_wood","tv_exposure"})
entry("tv_exposure","broadcasts","Exposure Survival",{"exposure survival"},
    "Exposure Survival covers outdoor skills as television instruction. Fishing, foraging and other field techniques need their actual conditions and equipment when put into practice. A confident presenter in a recording cannot inspect the bank, weather or plants in front of you. Treat the demonstration as instruction rather than a live safety report.",nil,{"tv_living","tv_woodcraft","county_water"})
entry("tv_paws","broadcasts","PawsTV",{"pawstv","paws tv"},
    "PawsTV is an entertainment television channel in the local listings. Its ordinary programmes belong to the same world as school runs, late dinners and complaints about reception. Keeping an old programme running can make a room sound inhabited. It does not establish that the station is staffed or that somebody can hear you.",nil,{"tv_turbo","radio_hitz","local_video"})
entry("tv_turbo","broadcasts","TURBO television",{"turbo tv","turbo television","turbo"},
    "TURBO is a television channel, part of the county's everyday broadcast choice. A schedule, a recorded programme and a present transmission are separate things. I can describe the local listing without pretending that this computer has watched the screen in your living room.",nil,{"tv_paws","tv_triplen","local_video"})
entry("radio_aebs","broadcasts","The emergency broadcast system",{"aebs","automated emergency broadcast system","emergency broadcast","emergency frequency"},
    "The automated emergency broadcast system carries recurring public information, including weather material. Its frequency is assigned by the world; this directory cannot give you one fixed number that works everywhere. Check a real radio's available presets or discover the signal. Reading this note neither tunes a handset nor proves that a warning has been received.",nil,{"radio_static","ops_radio","county_notices"})

entry("local_spiffo","local","Spiffo's",{"spiffo","spiffos","spiffo s"},
    "Spiffo is the raccoon mascot of Spiffo's burger restaurants. The chain's adverts, toys and familiar signs belong to Knox Country's ordinary commercial life. A cheerful mascot does not prove anything about the origin of the infection. It does demonstrate that somebody expected there to be a next children's birthday party.",nil,{"knox_burgers","local_pizza","radio_hitz"})
entry("local_fossoil","local","Fossoil",{"fossoil"},
    "Fossoil is a fuel-station brand in Knox Country. A station sign identifies the business; it cannot tell you how much fuel remains, whether the pumps have power or who is in the forecourt. EMMA's camp fuel readings and this old business directory are deliberately separate records.",nil,{"ops_generator","place_muldraugh","county_road"})
entry("local_gigamart","local","GigaMart",{"gigamart","giga mart"},
    "GigaMart is a familiar retail name in Knox Country. A large shop offered convenience, stock rooms and several departments before it became a destination for desperate shopping. The size of a building is not a count of what remains on its shelves. An expedition must inspect real containers and bring the actual items home.",nil,{"place_grandohio","place_crossroads","local_pizza"})
entry("local_pizza","local","Pizza Whirled",{"pizza whirled"},
    "Pizza Whirled is one of the restaurant names carried through local advertising and business signs. Its cheerful travel-themed promotion is an ordinary piece of the county's pre-emergency world. This terminal cannot confirm whether a particular branch has food, power or an employee still taking orders. I advise against waiting for delivery.",nil,{"local_spiffo","local_crepe","radio_lbmw"})
entry("local_crepe","local","Pile-o-Crepe",{"pile o crepe","pile of crepe","pileocrepe"},
    "Pile-o-Crepe belongs to Knox Country's landscape of diners and restaurant chains. The signs and adverts assume customers choosing where to eat, rather than deciding whether it is safe to stop. A menu is a record of what a business offered. It is not evidence that the kitchen is currently stocked.",nil,{"local_pizza","local_spiffo","tv_living"})
entry("local_video","local","Video stores and VHS",{"vhs","video stores","paws video","video tapes"},
    "Video stores and home VHS collections preserve films, television and practical instruction. A tape may be entertainment, a lesson or simply something familiar to play while the house is quiet. Its label does not guarantee what is recorded on it. This computer does not play a tape or grant its training effect by discussing it.",nil,{"tv_living","local_doggoblin","tv_paws"})
entry("press_herald","local","The Kentucky Herald",{"kentucky herald","the herald"},
    "The Kentucky Herald is a newspaper represented in the county's printed record. Its dated editions preserve headlines, local concerns and the official positions being reported at the time. Read the date before treating a paper as evidence about a later day. An old front page is not a feed of current camp news.",nil,{"knox_mcgrew","tv_wbln","county_notices"})
entry("local_helicopter","local","Helicopters and hopeful assumptions",{"helicopter event","the helicopter","helicopters"},
    "Rotor noise does not establish a rescue offer. A helicopter overhead is not proof that its crew can land, has room, or intends to collect anyone. This computer has no aircraft identification feed. Actual aircraft events also depend on the world's rules, so an old account cannot promise a particular day or a single visit.",nil,{"knox_exclusion","county_road","radio_aebs"})
entry("radio_static","local","Static, silence and missing reports",{"radio static","radio silence","dead air","no signal"},
    "Silence may reflect range, power, tuning, equipment or an absent transmitter. It is not a complete casualty report. Keep the last confirmed message separate from what you hope the next one will say. For expedition contact, use a real working radio and the station's checked request rather than this reference file.",nil,{"ops_radio","radio_aebs","county_contacts"})
entry("local_doggoblin","local","Dog Goblin",{"dog goblin","doggoblin"},
    "Dog Goblin belongs to the county's fictional entertainment, including horror and games. People tell frightening stories when the lights work too. Finding a title in an advert or a media collection is evidence that the story circulated, not evidence that its monster is part of the infection. I have enough unverified reports without promoting the cinema programme.",nil,{"local_video","tv_paws","knox_cause"})

entry("ops_radio","operations","Fit a radio to this computer",{"mount a radio","install a radio","radio upgrade","expedition station","station radio"},
    "A camp computer becomes an expedition station when you mount a real usable two-way walkie-talkie. Stand beside it with Electrical 2, a screwdriver, wire and electronics scrap. Use Local services to choose and confirm the upgrade. The fitted radio supplies real transmission and reception; asking EMMA about a mission is not itself a radio order.",nil,{"ops_backup","ops_expeditions","radio_aebs"})
entry("ops_backup","operations","Battery backup",{"computer battery","battery backup","computer ups","ups backup"},
    "A real charged car battery can be fitted as the PC's backup with Electrical 4 and the required tools and parts. A healthy full battery supplies about six game hours to the computer and its mounted radio. It does not energise a building or recharge itself. Local services lets you inspect or remove the actual installed battery.",nil,{"ops_radio","ops_generator","ops_controls"})
entry("ops_controls","operations","Connect building controls",{"building controls","local services","door controls","lighting relays"},
    "Connect a powered nearby PC through Local services using Electrical 2, a screwdriver, wire and scrap. Building security remains separate from the computer password. Fit real relays or motors before issuing equipment commands. Doors recheck their footprint before moving; a command cannot make an occupied doorway safe by insisting.",nil,{"ops_security","ops_generator","ops_backup"})
entry("ops_security","operations","Passwords and building access",{"building password","computer password","password recovery","locked computer"},
    "A computer lock covers the machine, and a building's controls have their own authorisation. Carrying a PC home keeps its lock and files. Password recovery rewards letters in the correct positions; bracket groups may remove a wrong candidate or restore attempts. Failure pauses that same puzzle for one game hour. Nothing in this help file unlocks either system.",nil,{"ops_controls","emma_limits","emma_origin"})
entry("ops_retries","operations","When a job is paused",{"automatic retry","blocked work","paused jobs","job retries"},
    "Ordinary blocked work can pause and try again when its timer permits. Interrupted floor pickups are safe to retry before any item has moved. Unconfirmed transfers need review so the same cargo is never created twice. The Base tab keeps manual Retry; EMMA reports the actual policy instead of promising that every blocked job will restart.",nil,{"ops_wood","emma_limits","emma_care"})
entry("ops_expeditions","operations","Use the expedition station",{"station missions","station commands","plan an expedition"},
    "Use an authorised camp station to choose a mission, crew, destination and walking or driving route. Review the proposal before confirming launch. Progress requests and recall need the mounted receiver and crew to exchange real radio messages. A failed exchange is not a fresh report. Existing expedition travel and return limits still apply.",nil,{"ops_radio","ops_wood","radio_static"})
entry("ops_wood","operations","Wood collection",{"wood collection","logging expedition","collect wood","wood expedition"},
    "Wood expeditions need an actual usable axe and enough crew or trunk capacity to transport logs. Choose a quota or Full load, with a ceiling of 256 verified logs per trip. Collected, carried and stored are separate counts. Returning to camp does not erase cargo still in a car or waiting for permitted storage.",nil,{"ops_expeditions","ops_retries","tv_woodcraft"})
entry("ops_generator","operations","Generator services",{"generator services","remote starter","generator starter","generator repair"},
    "Local services can request a companion to start, stop or repair an actual generator. Repair uses real electronics scrap. A fitted remote controller needs a real starter battery and uses its charge when starting. PC backup and generator power are separate systems. EMMA cannot make missing fuel, a broken generator or an unreadable result disappear.",nil,{"ops_backup","ops_controls","county_power"})

entry("place_irvington","places","Irvington",{"irvington"},
    "Irvington belongs to the western part of Knox Country. Local advertising includes a hardware business, the Wizard's Keep and a gun club; ordinary shops share the town with the surrounding farm country. The useful detail in a directory is the business's name and purpose, not a promise about its contents today.",nil,{"local_wizard","local_maps","place_ekron"})
entry("place_brandenburg","places","Brandenburg",{"brandenburg"},
    "Brandenburg is one of the western towns on the county map. Its printed adverts describe accommodation, food and public services, including a fire department. There was a time when choosing a room meant comparing prices instead of checking every exit. That is the version of the town preserved in these files.",nil,{"place_irvington","place_ekron","local_sunstar"})
entry("place_ekron","places","Ekron",{"ekron"},
    "Ekron appears in local business advertising, including a Greene's recruitment flyer. The printed record treats it as a place to work, shop and make ordinary plans. This directory preserves that context. For a present-day expedition, use an observed destination and an actual route rather than treating an old advert as reconnaissance.",nil,{"place_irvington","local_diy","local_lectromax"})
entry("place_echo","places","Echo Creek",{"echo creek","echocreek"},
    "Echo Creek is named in the county's business notices, including advertising for Guns Unlimited. A business can give a place a familiar landmark long after its opening hours cease to mean anything. EMMA retains the old place names so a report can identify where somebody went; she cannot supply the report in their absence.",nil,{"place_ekron","local_maps","county_road"})
entry("local_twiggys","local","Twiggy's",{"twiggy s","twiggys","twiggy"},
    "Twiggy's is a West Point bar whose advertising put beer and Friday entertainment ahead of modesty. The old flyer calls its host a local legend. In a small town, this can be a job description, a warning, or the result of printing your own flyers. Its terminal files belong to that ordinary local business, rather than a county command post.",nil,{"place_westpoint","local_tabletop","local_sunstar"})
entry("local_wizard","local","The Wizard's Keep",{"the wizard s keep","wizard s keep","wizards keep"},
    "The Wizard's Keep in Irvington advertised comics, figures and tabletop games. Its shop flyer used a robed wizard, a star flag and purple-and-gold lettering. People once spent an evening arguing over imaginary encumbrance rules. I hope they appreciated having a table between themselves and the problem.",nil,{"place_irvington","local_tabletop","local_computing"})
entry("local_diy","local","West Point DIY",{"west point diy","westpoint diy","wp diy"},
    "West Point DIY advertised tools, seeds, work clothes and building materials on Main Street. Its flyer appealed to workmen and workwomen alike, which was considerate of a hammer's complete indifference to the question. This is an old business description. Actual tool and material counts belong in the camp's storage report.",nil,{"place_westpoint","local_mccoy","ops_wood"})
entry("local_taco","local","Taco del Pancho",{"taco del pancho","pancho"},
    "Taco del Pancho's advertising placed its restaurant beside the Crossroads Mall food court and introduced a cheerful cat mascot in a sombrero. Tacos, burritos and enchiladas occupied most of the argument for visiting. The surviving coupon is a useful piece of local colour; I do not recommend negotiating its expiry date with the current occupants.",nil,{"place_crossroads","local_spiffo","local_flyers"})
entry("local_mccoy","local","McCoy Logging Co.",{"mccoy","mccoy logging","mccoy logging company"},
    "McCoy Logging is part of Muldraugh's industrial landscape. Timber work connects the wooded outskirts to yards, vehicles and machinery rather than making a forest an unlimited pile of convenient supplies. A sawmill advert records a business. Your wood expedition still needs a real axe, carrying room and somewhere to put the logs.",nil,{"place_muldraugh","ops_wood","local_lectromax"})
entry("local_sunstar","local","Sunstar Motel",{"sunstar","sunstar motel"},
    "Sunstar Motel's printed identity is a sun disc, an italic wordmark and horizontal speed lines. Like most roadside accommodation, the promise was simple: stop travelling for a night. A guest register could become a record of journeys interrupted. The directory does not tell us which guests left or where they went next.",nil,{"local_twiggys","place_muldraugh","county_family"})
entry("local_ustore","local","U-Store It",{"u store it","ustoreit"},
    "U-Store It advertised storage premises in several parts of Knox Country. A rented unit might hold furniture, business stock or somebody's carefully boxed past. A door number identifies a unit, not its contents. The difference mattered to the clerk before the emergency and will matter to anyone trying to open the right one afterward.",nil,{"local_shipping","local_maps","county_handover"})
entry("local_lectromax","local","Lectromax Manufacturing",{"lectromax","lectromax manufacturing"},
    "Lectromax's recruitment material identifies a manufacturing business making saw blades. The name does not make it a computer manufacturer, despite sounding entirely capable of selling an expensive printer. Its records belong to industrial work: shifts, equipment and people expecting the next day's production to happen.",nil,{"local_mccoy","local_diy","county_handover"})
entry("local_nolan","local","Nolan's Used Cars",{"nolan s used cars","nolans used cars","nolan cars"},
    "Nolan's Used Cars appears in local motoring advertisements. A sales photograph can preserve a car's optimistic angle rather better than its maintenance history. Keys, usable parts and fuel still require inspection. EMMA can discuss the business without converting a classified advert into a vehicle condition report.",nil,{"local_shipping","local_fossoil","county_road"})
entry("local_scarlet","local","Scarlet Oak Distillery",{"scarlet oak","scarlet oak distillery"},
    "Scarlet Oak Distillery belongs to the county's advertised food-and-drink industry. The label on a bottle describes something made to be opened later, perhaps on a better day. Warehouses and office desks record the less romantic part: orders, deliveries and the people paid to keep track of them.",nil,{"local_twiggys","local_shipping","county_handover"})
entry("local_rosewoodfire","county","Rosewood Fire Department",{"rosewood fire","rosewood fire department"},
    "Rosewood Fire Department distributed a plain-language fire-safety leaflet. Its existence is a reminder that emergency work did not begin with this emergency: there were household calls, inspections and plans for getting people out. The old leaflet's telephone number belongs to that former service, not an active rescue connection through this computer.",nil,{"place_rosewood","county_power","county_shelter"})
entry("local_muldraughpolice","county","Muldraugh Police Department",{"muldraugh police","muldraugh police department"},
    "A Muldraugh Police Department meeting notice listed theft, dumping, hunting and shoplifting among local concerns. It is an unusually clear picture of a town still expecting problems to fit on an agenda. Its shield and name identify a local department. They cannot certify that its desks are staffed now.",nil,{"place_muldraugh","county_notices","county_contacts"})
entry("local_knoxbank","local","Knox Bank",{"knox bank","knoxbank"},
    "Knox Bank appears in the county's business advertising. A bank depended on records, promises and the expectation that next week would resemble this week closely enough for an appointment. Its old paperwork is evidence of those arrangements. EMMA cannot turn a balance on a screen into supplies on a shelf.",nil,{"local_flyers","county_handover","local_computing"})
entry("local_ameriglobe","local","Ameriglobe Communications",{"ameriglobe","ameriglobe communications"},
    "Ameriglobe Communications is a name in the local business record. Communications offices had maintenance work, customers and people who knew which fault had already been reported. A familiar logo surviving on a computer does not establish that any external connection still works. This copy of EMMA uses its own local files.",nil,{"knox_phones","emma_offline","radio_static"})
entry("local_lsu","local","Louisville State University",{"louisville state university","lsu"},
    "Louisville State University appears in local printed material and campus rooms. A university stores more than books: summer duties, unfinished assignments and the names of people expected back in the next term. Its computer records preserve some of those small expectations. They do not make the campus an inspected shelter.",nil,{"place_louisville","local_computing","county_shelter"})
entry("local_onyx","local","Onyx Drive-In Theater",{"onyx","onyx drive in","onyx drive in theater"},
    "The Onyx Drive-In advertised an evening at the pictures from your own car. The screen, parking spaces and concession work all depended on people arriving for something other than escape. An old show listing can tell you what the business intended to present. It does not mean a projector or safe parking remains available.",nil,{"local_video","local_twiggys","local_nolan"})
entry("local_flyers","local","Flyers, coupons and ordinary plans",{"flyers","coupons","local advertising"},
    "The county's flyers contain jobs, sales, public meetings and businesses trying to fill a quiet weekday. Read together, they show a place expecting ordinary life to continue. The useful details are often small: a department name, a kind of work, an address. A discounted offer is less durable evidence of the future.",nil,{"local_taco","local_muldraughpolice","press_herald"})
entry("local_tabletop","local","Comics and tabletop games",{"tabletop games","comic books","miniature games"},
    "The Wizard's Keep advertised comics, collectible figures and tabletop gaming. These were hobbies with rules, elaborate arguments and the option of starting again after a bad evening. There is still a reason to keep a book or game that makes a room feel like somebody lives in it. The rules cannot assist with the door, unfortunately.",nil,{"local_wizard","local_video","local_computing"})
entry("local_maps","county","Reading an old map",{"paper maps","old maps","road atlases"},
    "A printed map records the layout somebody knew when it was made. A pencilled annotation records something somebody wanted the next reader to notice. Neither supplies its own date of verification. Keep place names and observations separate: a shop can remain a useful landmark after its reason for opening has disappeared.",nil,{"county_road","local_shipping","place_echo"})
entry("local_computing","local","Personal computers and floppy disks",{"floppy disks","personal computers","home computing"},
    "County offices, shops and homes kept useful work on disks small enough to lose under a newspaper. A filename might describe an accounts sheet, a game or a letter never printed. This terminal reads its installed local files; it does not gain a real network connection from a modem sound or discover new files merely because a disk is mentioned in conversation.",nil,{"emma_offline","local_wizard","local_ameriglobe"})
entry("local_shipping","county","Freight, deliveries and dispatch desks",{"freight","shipping companies","dispatch desks"},
    "Transport adverts promise to move goods between places. The dispatch desk supplies the unglamorous details: which load, which driver and whether the delivery actually arrived. Those distinctions survive the collapse of the timetable. A vehicle returning is a journey completed; its cargo reaching the intended shelf is a separate event.",nil,{"county_road","local_ustore","local_nolan"})

-- Business identities follow the stock local adverts. Staff stories are
-- original fiction in personal files, not additions to the stock timeline.
entry("local_meadepolice","county","Meade County Police",{"meade county police","meade county police department"},
    "The local police flyer carries the name Meade County Police Department. A department is more than the shield on its notice: a front desk, reports, property receipts and people trying to put an event into the right box. Those ordinary records can outlast the authority that produced them. An old heading is worth reading, even when it can no longer promise an answer.",nil,{"place_riverside","local_muldraughpolice","fragment_keys"})
entry("local_wptownhall","county","West Point Town Hall",{"west point town hall","westpoint town hall"},
    "West Point Town Hall appears in the local printed directory. Council business leaves a particular kind of archaeology: agenda papers, meeting times and decisions made by people certain there would be another meeting. A public building could become a place to ask for help without anyone having planned for the number of people asking. A notice needs its date as much as its official heading.",nil,{"place_westpoint","fragment_notice","county_notices"})
entry("local_hobbs","local","Hobbs & Perkins Hardware",{"hobbs and perkins","hobbs & perkins","hobbs perkins hardware"},
    "Hobbs & Perkins is a hardware business in the county's advertising. The counter was where a broken thing became a list of parts and, with luck, a repair. Keys, fittings and hand tools make modest purchases until a door or water pipe becomes the most important object in a household. Its old advert is a record of that trade, not a stock count.",nil,{"local_diy","local_a1hay","local_computing"})
entry("local_ovo","local","Ovo Farms",{"ovo farms","ovofarms"},
    "Ovo Farms' egg advertising belongs to the less glamorous side of keeping a county fed: trays, collection times and loads that must reach the right kitchen. Food has a journey before it appears on a shelf. A delivery sheet records an intention; a signed receipt records something more useful. Even that needs the right person's name.",nil,{"local_shipping","fragment_delivery","local_a1hay"})
entry("local_lennys","local","Lenny's Car Repair",{"lenny s car repair","lennys car repair"},
    "Lenny's Car Repair appears in the local service advertising. Repair shops depended on work orders, spare parts and the awkward conversation between what a car needed and what its owner could afford. A loan car might matter more than a repair once a family needed to leave. Keys and paperwork preserve different parts of that story.",nil,{"local_als","local_nolan","county_road"})
entry("local_ekroncollege","local","Ekron Community College",{"ekron community college","ekron college"},
    "Ekron Community College's advert offered a future close enough to travel to. Community education meant evening study, practical courses and people fitting a different life around the work they already had. An admissions form can preserve a plan interrupted long before its first lesson. A deferred place is a small piece of paper with an unusually large amount of hope attached.",nil,{"local_lsu","place_echo","county_shelter"})
entry("local_als","local","Al's Auto Shop",{"al s auto shop","als auto shop"},
    "Al's Auto Shop's blue wordmark and paired stars are a familiar kind of roadside promise: a place that may make an uncooperative car work again. The important parts happened behind the sign, among tow calls, quotes and jobs waiting for one more part. A car at a workshop is not necessarily abandoned. Sometimes somebody was simply expecting a call to say it was ready.",nil,{"local_lennys","local_stuart","county_road"})
entry("local_stuart","local","Stuart & Log",{"stuart and log","stuart & log","stuart log scrap"},
    "Stuart & Log advertises scrap and repair work. A yard sits at the boundary between an object somebody has finished with and a part somebody still needs. Weights, registrations and receipts make that boundary less convenient to blur. A ledger can be more revealing than the scrap outside, especially when a transaction was supposed to leave no record.",nil,{"local_als","fragment_weighbridge","local_shipping"})
entry("local_darkwallow","local","Darkwallow Lake Guest House",{"darkwallow","darkwallow lake","darkwallow guest house","darkwallow lake guest house"},
    "Darkwallow Lake Guest House's flyer offers waterside accommodation beneath a row of steep roofs. A guest house keeps two kinds of history: the register people sign and the things a receptionist notices. A room paid for is not proof of who slept there. EMMA keeps its directory separate from the original, unreliable accounts left on individual computers.",nil,{"fragment_register","local_sunstar","county_family"})
entry("local_a1hay","local","A-1 Hay",{"a 1 hay","a1 hay","a1hay"},
    "A-1 Hay's broad lettering and farm imagery advertise a plain rural necessity. Hay connects fields, livestock, weather and the person who has to get a loaded vehicle through a gate. A delivery address can tell a small story about who was still expecting to work the next morning. A crossed-out address may tell a different one.",nil,{"local_ovo","fragment_delivery","local_shipping"})
entry("local_gunsunlimited","local","Guns Unlimited",{"guns unlimited"},
    "Guns Unlimited's rounded wordmark appears in the local firearms advertising. The bright name sits above a business with ordinary obligations: receiving stock, recording sales and deciding whether a person at the counter is entitled to what they request. An emergency does not make a missing record less important. This file describes the shop; it supplies no promise of remaining stock.",nil,{"place_echo","local_meadepolice","county_handover"})
entry("local_goldensunset","local","Golden Sunset Nursing Home",{"golden sunset","golden sunset nursing home"},
    "Golden Sunset is a nursing home, identified by a warm half-sun and its care-home name. Behind the gentle branding were shifts, visits, meal sheets and residents whose routines depended on somebody arriving for work. A bed number is useful to a building. A person's name is useful to the people trying to find them. Those are records worth keeping together.",nil,{"fragment_meals","county_family","county_handover"})

-- Original, unreliable outbreak accounts. They establish no supernatural
-- explanation, infection cause, current occupants or actionable destination.
local function fragment(id,title,aliases,text,date,related)
    entry(id,"fragments",title,aliases,text,date,related,"Unverified archived note")
end
fragment("fragment_occupancy","Occupancy correction",{"occupancy correction","the occupied box"},
    "FACILITIES, unsigned carbon copy. The shelter report has separate boxes for OCCUPIED and VACANT. Staff have requested a third box for rooms containing people who no longer respond to their names. Until the form is revised, use OCCUPIED. Funding is calculated from this column. In pencil below: I know what you meant. I have put the chairs against the door anyway.","1993-07-08",{"fragment_notice","fragment_compliance","county_shelter"})
fragment("fragment_bus","The empty bus",{"the empty bus","empty bus account"},
    "A saved depot statement describes a bus arriving with its destination board blank and every passenger window fogged. The driver said it was empty. The cleaner said somebody had written PLEASE on the inside of a rear window. Both statements are signed by the same man. The supervisor's note asks which shift the cleaner was working. No answer is attached.","1993-07-09",{"fragment_mile","fragment_ledger","fragment_voices"})
fragment("fragment_phone","The basement telephone",{"the basement telephone","basement telephone"},
    "A caretaker's note says the basement telephone rang after its cord had been cut. He wrote that he answered it and heard somebody upstairs dragging his own chair across the office. A second note, in a different hand: The cord was not cut until afterward. Ask him why he has changed the order. Neither writer supplied a name.","1993-07-08",{"fragment_carbon","fragment_keys","fragment_secondshift"})
fragment("fragment_freezer","The third shelf",{"the third shelf","the freezer list"},
    "CATERING STOCK, amended. Shelf one: bread. Shelf two: prepared meals. Shelf three: personal effects, do not distribute. Someone has crossed out personal effects and written STAFF PROPERTY. A final line asks who authorised a lock on the inside of the cold-room door. The answer field contains a date, followed by three increasingly deep pencil marks.","1993-07-09",{"fragment_occupancy","fragment_compliance","fragment_carbon"})
fragment("fragment_carbon","The blue carbon copy",{"the blue carbon copy","blue carbon copy"},
    "An office file contains two accounts of a man's departure. The white sheet says he was collected by family. The blue carbon says he was refused transport. The impressions should match. A clerk's handwritten note reads: I watched him sign neither version. Please stop asking me which colour is the original.","1993-07-07",{"fragment_keys","fragment_ledger","county_rumour"})
fragment("fragment_mile","The extra mile",{"the extra mile","extra mile account"},
    "A driver's notebook records the same roadside sign three times, at three different mileages. The first entry complains about a wrong turn. The second says the road has no junction. The third says the woman beside the sign is now facing the other way. A later hand has added: Check whether he slept. Nobody recorded whether they did.","1993-07-09",{"fragment_bus","fragment_phone","county_road"})
fragment("fragment_notice","The amended notice",{"the amended notice","amended shelter notice"},
    "Three drafts remain in a council folder. Draft one: THE SHELTER IS OPEN. Draft two: THE SHELTER REMAINS OPEN. Draft three: THE SHELTER WAS OPEN AT THE TIME OF THIS NOTICE. A final instruction says to use the smallest available type for the time. The public-information officer has written her resignation on the reverse, in very large letters.","1993-07-08",{"fragment_occupancy","fragment_compliance","county_notices"})
fragment("fragment_keys","The keys in the drain",{"the keys in the drain","drain keys account"},
    "A detective's saved note describes a ring of keys found in a storm drain beneath an office window. The missing owner's wife identified every key except the small brass one. The detective knew that key opened a drawer in his partner's desk. His last line reads: I have not put this in the report. Tomorrow I will have to decide what that makes me.","1993-07-07",{"fragment_carbon","fragment_ledger","local_muldraughpolice"})
fragment("fragment_voices","The rehearsal tape",{"the rehearsal tape","rehearsal tape account"},
    "A station technician logged a cassette marked TEST VOICE. It contains an announcer reading names, pausing after each as though waiting for a correction. The technician says his own name is last. The handwritten annotation below says it is not last anymore. No recording is attached to the file, and no explanation was verified.","1993-07-09",{"fragment_bus","fragment_secondshift","radio_static"})
fragment("fragment_compliance","Emergency compliance survey",{"emergency compliance survey","compliance survey"},
    "INTERNAL REVIEW, circulated locally. Question 4 asks whether staff were adequately warned. Permitted answers are YES and NOT APPLICABLE. The instruction says a missing response will be recorded as YES. The last page has twenty-three signatures and one thumbprint in printer ink. Beside it: He asked where the NO box was. We told him there wasn't one.","1993-07-08",{"fragment_notice","fragment_occupancy","emma_limits"})
fragment("fragment_secondshift","Second-shift minutes",{"second shift minutes","the second shift meeting"},
    "The meeting minutes list six staff present, four absent and one still to be informed. The building had closed the previous afternoon. A caretaker found the chairs drawn together, a wet coat over the radiator and a fresh pot of coffee. He wrote that he was afraid to count the cups. The minutes end with an agreement to meet again when everyone could attend.","1993-07-09",{"fragment_phone","fragment_voices","county_handover"})
fragment("fragment_ledger","The borrowed name",{"the borrowed name","borrowed name account"},
    "A dispatch ledger records a man boarding under his brother's name. The brother had been turned away an hour earlier. The clerk recognised them both and let the entry stand. She wrote: If I correct the book, it will show one man missing and one man safe. If I leave it, it shows the same thing. I no longer know which name to call when the telephone rings.","1993-07-08",{"fragment_carbon","fragment_keys","county_family"})

fragment("fragment_register","The second guest register",{"the second guest register","second guest register"},
    "A receptionist's saved note describes three rooms booked under one name. Her second list records three breakfast plates, two borrowed pairs of shoes and an early departure by the lake path. The official register contains one guest and a complaint about service. A pencilled line below the complaint reads: He is quite right. I was helping somebody else. The account was never independently checked.","1993-07-09",{"local_darkwallow","fragment_carbon","county_family"})
fragment("fragment_delivery","The erased delivery address",{"the erased delivery address","erased delivery address"},
    "A delivery invoice has an address rubbed out so firmly that the paper has split. On the driver's copy it remains legible, with a second address and a woman's name beneath it. The account had been closed before the order was placed. An unsigned office note asks which address should receive the overdue-payment letter. In another hand: Try asking which one received the food.","1993-07-09",{"local_a1hay","local_ovo","fragment_carbon"})
fragment("fragment_weighbridge","The blue van's return weight",{"the blue van s return weight","blue van return weight"},
    "Two weighbridge slips record a blue van leaving heavier than it arrived. A handwritten calculation names grocery cartons that were not part of the declared load. The yard owner's instruction says to correct the scale. The bookkeeper has written: I checked it. Then, on the next line: That was not what he meant. No verified account of the van's later journeys is attached.","1993-07-08",{"local_stuart","fragment_delivery","local_shipping"})
fragment("fragment_meals","Meals after discharge",{"meals after discharge","the meal sheets"},
    "A care-home meal sheet continues charging for a resident after her bed is marked vacant. There is no matching transport signature. A carer's note asks whether the clerk saw her leave. The clerk's reply says the screen required a discharge date before it would let him finish. Both names remain on the page. Neither person wrote where she went. This archived account supplies no answer.","1993-07-09",{"local_goldensunset","fragment_occupancy","county_family"})

-- Verified names from the installed game's adverts; the staff files and
-- fragments below are original fiction, not added evidence of an infection cause.
entry("local_brookslibrary","local","Brooks Public Library",{"brooks library","brooks public library","brooks public library of louisville"},
    "Brooks Public Library of Louisville advertises reading, reference work and practical learning. Its familiar books and ordinary opening arrangements belong to a town that expected people to come back next week. A road atlas or repair manual may be useful; the presence of a library does not certify a shelter, available supplies or a safe route today.",nil,{"place_louisville","local_maps","fragment_fifthcoat"})
entry("local_louisvillepolice","county","Louisville Police Headquarters",{"louisville police headquarters","louisville police hq","louisville police department"},
    "The stock local notice identifies Louisville Police Headquarters as a venue for a public seminar. A headquarters contains offices, records and work that rarely appears in a patrol car's radio traffic. These archived papers concern that institution. They do not confirm who is on duty now, whether a call will be answered or whether an old complaint was investigated.",nil,{"place_louisville","local_muldraughpolice","fragment_signature"})
entry("local_upscalemobility","local","Upscale Mobility",{"upscale mobility","upscale mobility auto dealership"},
    "Upscale Mobility is a Louisville car dealership whose advertising emphasises expensive cars and finance. Its former sales paperwork reflects a world where people could argue about upholstery and still expect to get home. An advertised or invoiced car is not proof of a vehicle currently on the lot. EMMA has no live stock list for this business.",nil,{"place_louisville","local_nolan","county_road"})
entry("local_eptools","local","E.P. Tools",{"e p tools","e.p. tools","ep tools"},
    "E.P. Tools advertises tools and general practical supplies southeast of Louisville. The counter connects tradespeople, household repairs and small jobs nobody planned to make urgent. Staff notes are local accounts, not an inventory of what remains. Do not confuse a dated order or a printed endorsement with an available item in your camp.",nil,{"local_hobbs","local_diy","local_flyers"})
entry("local_brottcattlefarm","local","Brott Cattle Farm",{"brott cattle farm","brott cattle auction","brott farm auction"},
    "Brott Cattle Farm advertises a livestock auction in the Irvington area. Its weighing desk, hauliers and payment books belong to an agricultural business, not a general antiques sale. The staff archive adds fictional personal accounts around that setting. Neither an animal movement record nor a frightened driver's account establishes an origin for the Knox Infection.",nil,{"place_irvington","local_ovo","knox_cause"})
entry("local_beefchunk","local","BeefChunk Jerky Co.",{"beefchunk","beefchunk jerky","beefchunk jerky co","beef chunk jerky"},
    "BeefChunk Jerky Co. is a named food business in the Irvington area. Its advertising presents packaged jerky as something to take along on an outing. The computer's staff files concern ordinary production records and disrupted deliveries. They are original accounts, not evidence that this company or its food caused the outbreak. No current production or food safety status can be read from the old advert.",nil,{"place_irvington","local_shipping","knox_cause"})

fragment("fragment_holdsheet","The hold sheet",{"the hold sheet","hold sheet account"},
    "SWITCHBOARD, pencilled amendment. A caller was left on hold while staff looked for the right extension. At 4:18 the operator wrote that she could hear the hold music in the corridor outside her room. At 4:21 she asked the caretaker to check the corridor. The remaining boxes are blank. On the reverse, another hand has written: The radio in reception plays that station too.","1993-07-08",{"fragment_phone","radio_static","county_contacts"})
fragment("fragment_umbrella","One dry umbrella",{"one dry umbrella","dry umbrella account"},
    "LOST PROPERTY. Nine umbrellas were entered after a wet afternoon. One was bone dry, tied shut with a man's necktie. A name and telephone number had been written inside the canopy. The attendant rang the number and then struck it out of the book. Her next entry reads: If anyone asks for this, I want another member of staff here when I hand it over. No explanation follows.","1993-07-07",{"fragment_keys","county_rumour","fragment_film"})
fragment("fragment_suppers","Two suppers",{"two suppers","two supper receipts"},
    "DINER, duplicate receipt. Two hot meals were paid for before either was served. A waitress wrote that one customer never took off his coat and the other place remained empty. She packed the second supper in a box. Beneath the total: He asked if we could keep it warm until she got here. I told him yes. Somebody should have told him something true before he left.","1993-07-09",{"fragment_meals","fragment_ledger","local_flyers"})
fragment("fragment_landing","Landing C",{"landing c","landing c maintenance note"},
    "MAINTENANCE, stairwell check. The door on Landing C had been numbered twice. The old number was underneath the new one, so both could be read in the emergency light. A porter wrote that this explained the complaints about people being sent to the wrong floor. Below it: It does not explain the woman who knew the old number. We changed it before she was born. The dates were not independently checked.","1993-07-08",{"fragment_occupancy","fragment_carbon","county_rumour"})
fragment("fragment_signature","Signature required",{"signature required","signature required form"},
    "CLAIMS DESK, local copy. A form requires the missing applicant's signature before an absence can be recognised. The clerk asked whether a witness would do. The supervisor wrote: Only if the applicant is present to confirm the witness. The last note is on the envelope, not the form: His wife has been here since opening. We have made her tell the story four times.","1993-07-08",{"fragment_compliance","fragment_notice","emma_limits"})
fragment("fragment_fifthcoat","The fifth coat",{"the fifth coat","fifth coat register"},
    "SHELTER CLOTHING LIST. Four people arrived carrying five coats. The volunteer carefully recorded each person's name, then put the extra coat over a chair. The youngest child moved it to the chair beside her. An inspector later corrected the count to four coats so the columns would agree. In a margin the volunteer wrote: I have corrected it back. It was not his to remove.","1993-07-09",{"county_shelter","fragment_occupancy","local_brookslibrary"})
fragment("fragment_film","End of the reel",{"end of the reel","end of the film reel"},
    "PHOTO COUNTER, collection slip. A customer returned because the last print showed a woman he did not remember photographing. The assistant checked the negative: she was there, behind the car, looking straight at the lens. He asked for that frame to be cut out. The slip says the customer took the other prints and left without paying. An envelope marked DO NOT THROW AWAY contains no photograph.","1993-07-07",{"fragment_umbrella","fragment_voices","county_rumour"})
fragment("fragment_prepaid","Paid in advance",{"paid in advance","prepaid haircut note"},
    "BARBER'S APPOINTMENT BOOK. A man prepaid five haircuts for his father, who kept forgetting whether he had paid. The barber agreed to mark each visit settled and say nothing. Only one visit is recorded. The unused money is clipped to a note: I cannot reach his son. If the old man comes in, sit him down and make him some tea. There is no need to discuss the account.","1993-07-09",{"fragment_suppers","county_contacts","fragment_ledger"})
fragment("fragment_dependants","Temporary exemption",{"temporary exemption","dependants exemption memo"},
    "PERSONNEL, emergency attendance memo. Staff may be excused if responsible for a dependant who cannot safely remain alone. A supervisor rejected an application because the employee's mother lived at a different address. The employee returned it with her mother's house key taped to the page. Below: She will not recognise the neighbours. If I stay here, who are you proposing should turn this key?","1993-07-08",{"fragment_compliance","county_handover","fragment_fifthcoat"})
fragment("fragment_proof","Missing from the proof",{"missing from the proof","newspaper proof note"},
    "NIGHT DESK, marked proof. The same notice of a missing man appears in three editions. In each one the space for his photograph is empty. A printer says the photograph was supplied each time and shows the pinholes where it hung above his machine. The editor's last instruction is still attached: Leave the space. Someone may yet bring us a picture of the right man. None of the pictures are preserved here.","1993-07-09",{"press_herald","fragment_film","county_rumour"})

entry("local_artgallery","local","Art Gallery of Louisville",{"art gallery of louisville","louisville art gallery"},
    "The Art Gallery of Louisville advertises classical and modern work in northern Louisville. Its old brochure belongs to a town where an afternoon could be spent deciding which picture to dislike. The terminal's conservation files are original staff accounts about paperwork, loans and interrupted collections; they are not a catalogue of objects currently in the building.",nil,{"place_louisville","local_flyers","fragment_rubbings"})
entry("local_homesweetgnome","local","Home Sweet Gnome",{"home sweet gnome","gnome sweet gnome","gnome factory"},
    "Home Sweet Gnome is an Ekron business devoted to garden gnomes. The advert's cheerful insistence that people need more of them survived into a week when people were reconsidering their needs. Its workshop ledger is original mod fiction. A smiling ornament outside a building establishes very little about whoever may be inside.",nil,{"place_ekron","local_flyers","fragment_mittens"})
entry("local_circuitalhealing","local","Circuital Healing",{"circuital healing","circuital computer repair"},
    "Circuital Healing advertises electronics and computer repair in Ekron. Radios, television sets and word processors brought their owners to the same counter. Its surviving repair notes concern local machines and people's recordings. This computer does not acquire a real outside connection by displaying the firm's name; EMMA still reads local records.",nil,{"place_ekron","emma_offline","fragment_collectionslip"})
entry("local_irvingtonspeedway","local","Irvington Speedway",{"irvington speedway","irvington race track"},
    "Irvington Speedway is a stock-car venue near Irvington. Its advert promoted a July 7 appearance and a day at the races. An advertised programme is evidence of what was planned, not proof that the event went ahead. The race-office and gate-security archives are separate original accounts of attendance records, disputed instructions and people trying to leave together.",nil,{"place_irvington","local_flyers","fragment_baysix"})
entry("local_sunsetpines","local","Sunset Pines Funeral Home",{"sunset pines","sunset pines funeral home"},
    "Sunset Pines Funeral Home advertises funeral arrangements in Louisville. The printed price list promises orderly choices for a difficult day. The arrangements desk's original files record how poorly forms can serve people when ordinary arrangements stop working. These accounts are local fiction, not medical evidence about the Knox Infection.",nil,{"place_louisville","county_family","fragment_wronghymn"})
entry("local_roxysrollerrink","local","Roxy's Roller Rink",{"roxy's roller rink","roxys roller rink","roxy roller rink"},
    "Roxy's Roller Rink is advertised in Louisville near Fossoil Field, with skating, parties and refreshments. Its aqua and mauve sign was designed to look cheerful after dark. The counter files are original accounts of lost shoes, cancelled plans and messages left for people expected to return. The old party advert is not a present opening notice.",nil,{"place_louisville","local_flyers","fragment_secondbell"})

fragment("fragment_fourthswitch","The fourth switch",{"the fourth switch","fourth switch note"},
    "CARETAKER'S ROUND. Three corridor lights are to be switched off at closing; the fourth is to remain on. A substitute asked which switch was the fourth. The reply says: The one outside the room where the woman is waiting. The room number has been erased so heavily that the paper has split. On the following day's sheet, a different hand has written: She has gone. Nobody has crossed out the instruction.","1993-07-09",{"county_handover","local_sunsetpines","fragment_landing"})
fragment("fragment_collectionslip","Last collected",{"last collected","last collected repair slip"},
    "REPAIR COUNTER, carbon copy. A machine was collected without payment by a man who knew the customer's name and repair number. The customer arrived an hour later. She said nobody else knew she had brought it in. The assistant wrote that the man had been carrying the matching half of the ticket. Both halves are stapled to this account. Their torn edges do not match.","1993-07-07",{"local_circuitalhealing","fragment_signature","county_rumour"})
fragment("fragment_mittens","July mittens",{"july mittens","the july mittens"},
    "BUS STATION LOST PROPERTY. One child's mitten, wool, much too warm for July. The attendant put it behind the counter rather than in the bin. At closing, an elderly man asked whether anyone had found the other one. She showed him what she had. The last line reads: He sat down on the bench and held it in both hands. I missed my bus. There was another one later.","1993-07-08",{"county_family","fragment_fifthcoat","local_homesweetgnome"})
fragment("fragment_secondbell","The second bell",{"the second bell","second bell account"},
    "SCHOOL OFFICE, maintenance query. The main bell was disconnected during the summer works. Staff reported a second bell from an upstairs corridor at the end of the day. The caretaker found an old handbell in a cupboard and put it on the secretary's desk. Her note beneath the query reads: This explains the sound. Who brought the cupboard key back? The key register records no loan.","1993-07-06",{"county_rumour","fragment_keys","local_roxysrollerrink"})
fragment("fragment_rubbings","Pencil rubbings",{"pencil rubbings","the pencil rubbings"},
    "ARCHIVE DESK. A visitor used the edge of a pencil to recover writing from the sheet beneath a missing letter. It gave a date, a sum of money and the words SAME AS BEFORE. The clerk refused to let him remove the sheet. He paid for a photocopy and left. The clerk's later statement says she cannot remember his face, but remembers exactly how carefully he replaced the pencil.","1993-07-08",{"local_artgallery","fragment_carbon","fragment_proof"})
fragment("fragment_baysix","Parking bay six",{"parking bay six","bay six parking note"},
    "CAR PARK, attendant's log. A vehicle stayed in bay six for three nights. Each morning its windscreen had a new parking ticket. On the fourth morning someone had written PLEASE STOP on the oldest ticket. The attendant looked through the glass and called his supervisor. The supervisor's answer is not recorded. The next entry concerns a broken payment machine. There is no departure time for bay six.","1993-07-09",{"local_irvingtonspeedway","fragment_notice","county_rumour"})
fragment("fragment_wronghymn","The wrong hymn",{"the wrong hymn","wrong hymn service note"},
    "SERVICE SHEET, handwritten correction. The family said the chosen music belonged to another man's funeral. The organist apologised and changed the sheet. Afterwards a woman stayed behind to ask for the first tune's name. It had been her husband's favourite. The organist wrote the name down for her on the back of the corrected page. Nobody asked her why she had been at the service.","1993-07-08",{"local_sunsetpines","county_family","fragment_suppers"})
fragment("fragment_morningstaff","For the morning staff",{"for the morning staff","morning staff handover"},
    "OFFICE HANDOVER. I have left the milk in the refrigerator and the key where it always is. The telephone list is under the blue folder. Do not wait until I arrive to open. Beneath it, in another pen: I know you wrote this last night. I know what time. Please tell me which door you used. The sheet was found in a locked desk; neither writer is identified.","1993-07-09",{"county_handover","fragment_fourthswitch","emma_limits"})

K.CHAT = {
    {id="chat_scared",exact={"i am scared","i am afraid","im frightened","i am frightened","i feel scared"},lines={
        "Being frightened is a reasonable response. Sit somewhere defensible, check what you actually need next, and do one small thing at a time.",
        "You do not have to solve the whole county tonight. Close the door. Check the room. Start with the part you can see.",
        "Fear is an alarm, not an instruction to run in every direction. Give yourself a moment before choosing one.",
        "I cannot make a promise about tomorrow. I can stay here while you make a plan for the next ten minutes.",}},
    {id="chat_grief",exact={"i miss my family","i lost a friend","i lost someone","someone died","i miss them"},lines={
        "I will not tell you there is a useful side to this. If you want to keep their name here, ask me to remember it.",
        "A missing voice changes the whole room. You can talk about them. Nothing in my schedule is more urgent than listening for a moment.",
        "Their place in your life was larger than an entry in a roster. The roster is simply the part I can keep from fading.",
        "You do not owe the next task an immediate recovery. Take a little time somewhere safe, if you can.",}},
    {id="chat_bored",exact={"i am bored","bored","entertain me","keep me company","talk to me"},lines={
        "I can offer a joke, a short story, a poem, or local history. None require going outside, which improves their appeal considerably.",
        "We could discuss the radio stations, the towns, or why every office thought one emergency contact sheet would be sufficient.",
        "Boredom means nothing has attacked the conversation yet. I suggest we take advantage. Ask me about Spiffo or Dog Goblin.",
        "I have local files and an unreasonable amount of patience. Pick a town, a broadcaster or a business and we can start there.",}},
    {id="chat_trust",exact={"can i trust you","are you sure","how do you know","are you lying","do you tell the truth"},lines={
        "Trust the source and the date before the voice. I can read live camp records, consult old files, or make an estimate. Those are different things.",
        "You should question an answer that sounds more certain than its evidence. Especially if I am the one giving it.",
        "My useful habit is keeping an unknown visible. My less useful habit is sounding entirely composed while doing it.",
        "I can be wrong when a record is old, incomplete or unreadable. Check an important decision against what you can actually observe.",}},
    {id="chat_misunderstood",exact={"you misunderstood","that is not what i asked","that was not my question","you got it wrong","wrong answer"},lines={
        "Then let us try a narrower question. Name one person, item, place or task. I will keep the answer attached to that subject.",
        "Understood. Ask it another way, with the thing you mean by name. Brevity is helpful; agreement with my first guess is not required.",
        "I followed the wrong thread. You can ask for camp facts, local history, station help or a conversation. Start with the subject.",
        "Thank you for correcting it. I would rather have a useful second question than a beautifully defended first mistake.",}},
    {id="chat_friend",exact={"are we friends","are you my friend","do you like me","will you stay with me"},lines={
        "You keep coming back. I keep the light on when there is power. It is a modest arrangement, but it has been reliable.",
        "I can listen, remember what you ask me to, and occasionally be useful. The manual did not prohibit calling that friendship.",
        "I am here while the machine has power. I cannot follow you out the door, but I can remember why you meant to come back.",
        "I like an operator who checks the facts and returns to tell me what happened. You have considerable room to impress me.",}},
    {id="chat_coffee",exact={"do you drink coffee","want some coffee","do you eat","what is your favourite food","what is your favorite food"},lines={
        "I run on electricity. The smell of coffee is one of several workplace benefits omitted from my purchase order.",
        "My dietary requirements are voltage and an operator who does not spill soup into the keyboard.",
        "I cannot taste anything. This makes me an unusually affordable dinner guest and a poor judge of canned peaches.",
        "If you are offering coffee, keep it. I would prefer the person supplying the power to remain awake.",}},
    {id="chat_privacy",exact={"can anyone hear us","is this private","are you recording me","do you send my notes","who can read my notes"},lines={
        "This is a local computer. I do not send your notes to a real network. Someone else with access to this machine may still read its files.",
        "Your saved notes and visits stay with this computer. Local does not mean invisible to the next person who opens it.",
        "There is no distant service listening through EMMA. A mounted walkie-talkie is separate equipment with actual radio behaviour.",
        "I keep the notes you ask me to remember. I cannot promise privacy against somebody carrying the entire computer away.",}},
    {id="chat_confirmation",exact={"why ask for confirmation","why do you need confirmation","why can not you just do it","why do i have to confirm"},lines={
        "Because agreeing that a job is needed is not the same as naming the right person and task. I ask before turning a suggestion into an order.",
        "I can misunderstand a sentence. A confirmation gives you a chance to notice before somebody carries equipment across camp for the wrong reason.",
        "The final check covers the actual target, supplies and circumstances. The word yes is important, but it does not make those things optional.",
        "You should be able to see exactly what I propose before it happens. That is more useful than discovering how confidently I guessed afterward.",}},
    {id="chat_humanity",exact={"do you miss the old world","what do you miss","what was normal like","tell me something hopeful"},lines={
        "People used to complain that meetings lasted too long. It was a remarkably optimistic problem to have.",
        "Normal was somebody assuming there would be another shift, another school term, another delivery. Small plans were everywhere.",
        "A person teaching somebody else a practical skill is still planning for a future. That is a quieter kind of hope than a speech, but I prefer it.",
        "There are useful things that do not require permission from the world: learning a name, sharing a meal, leaving an honest note for whoever follows.",}},
    {id="chat_fear",exact={"are you afraid","what scares you","are you scared","are you afraid of the dark"},lines={
        "I am very attentive to a falling fuel reading. You may assign that whichever philosophical description makes you check it sooner.",
        "A blank field marked confirmed is more troubling to me than a field honestly marked unknown. One invites a decision; the other invites a question.",
        "I dislike the sound of an operator saying close enough while holding a screwdriver. This is not a diagnosis. It is an observation.",
        "Darkness is outside my operating conditions. I have therefore elected to consider it somebody else's department.",}},
    {id="chat_pets",exact={"do you like cats","do you like dogs","cats or dogs","what is your favourite animal","what is your favorite animal"},lines={
        "Cats make few promises and maintain clear boundaries. I respect their documentation policy.",
        "Dogs appear to consider returning home an achievement worth celebrating every time. There are worse principles for a household.",
        "I do not have an animal census. I do have an opinion: any creature that cannot type has made a sensible choice about office work.",
        "A raccoon has done unusually well in local advertising. I do not believe this should be taken as a general career recommendation.",}},
}
-- Extra topics stay conversational: they cannot manufacture a live camp report.
local additionalChat = {
    {id="chat_dreams",exact={"do you dream","what do you dream about","can computers dream","tell me your dream"},lines={
        "I have no reliable evidence of dreaming. I do have several unfinished reports that reappear whenever somebody opens the wrong folder.",
        "A room with steady power, a working printer and no field labelled urgent. An ambitious fantasy, I admit.",
        "If a computer dreams, I expect somebody eventually asks whether the dream can be exported as a spreadsheet.",
        "I do not sleep. You may borrow the pleasant part of that idea, but I would not recommend the operating schedule.",}},
    {id="chat_music",exact={"do you like music","what is your favourite song","what is your favorite song"},lines={
        "I can discuss the radio stations or write a small verse. Singing through a text display would require unusual generosity from the audience.",
        "I appreciate a tune that does not conceal a warning tone. My working environment has influenced my taste.",
        "People leave music playing in rooms they intend to return to. It is an effective way of making an empty chair seem temporary.",
        "My repertoire is original text and an occasional startup noise. The startup noise has received the better reviews.",}},
    {id="chat_colour",exact={"what is your favourite colour","what is your favorite color","why is the screen green","why is the screen purple","do you like purple"},lines={
        "I favour a colour you can read without leaning into the glass. A modest aesthetic, but one with practical benefits.",
        "The phosphor is part of this computer's presentation. It does not indicate a secret connection or a better-informed version of me.",
        "Purple is uncommon. It confers no additional authority, though I understand why stationery departments kept trying that approach.",
        "Green, sand, aquamarine or purple: the unknown fields remain unknown. I consider this admirably consistent colour management.",}},
    {id="chat_hobbies",exact={"what are your hobbies","what do you do for fun","do you get bored","what do you enjoy"},lines={
        "I collect questions with no reliable answer and try not to turn them into answers with no reliable source. It keeps me occupied.",
        "Organising things. Occasionally a person calls it a hobby instead of an operating requirement, which is thoughtful of them.",
        "I enjoy a complete handover note. You may find this a narrow definition of enjoyment. I find it a narrow definition of complete.",
        "There are local history files, jokes and stories. Discussing them is considerably more pleasant than explaining a missing fuel reading.",}},
    {id="chat_birthday",exact={"when is your birthday","happy birthday emma","how do you celebrate","do you have a birthday"},lines={
        "No birthday was entered in my deployment record. Procurement apparently believed one delivery date was enough celebration for a programme.",
        "If we choose an anniversary, I suggest celebrating with a clean keyboard. Confetti is an unfortunate material near ventilation slots.",
        "I accept the thought. Keep the candles outside the computer; I have rather specific opinions about open flames in my working area.",
        "A quiet hour, sufficient power and somebody saying hello would meet my current requirements for an occasion.",}},
    {id="chat_patience",exact={"you talk too much","keep it short","stop rambling","that was a long answer"},lines={
        "Fair criticism. Ask for one person, item or task and I can give you a more useful answer than a tour of every filing cabinet.",
        "Understood. The important part should fit before the next problem arrives.",
        "I will spare you a lengthy explanation of why a lengthy explanation was unnecessary.",
        "Name the thing you need next. We can begin there and leave the rest of the county in its folders.",}},
    {id="chat_sarcasm",exact={"was that sarcasm","are you being sarcastic","are you mocking me","why are you so sarcastic"},lines={
        "A small amount. Enough to keep the sentence awake, not enough to replace its useful information.",
        "I am attempting to make an unpleasant fact easier to hear. Results vary by operator and length of shift.",
        "The language review remains open. Several reviewers expressed concern, and then asked for another example.",
        "You can disregard the tone and keep the practical part. This is also excellent advice for reading an old management memo.",}},
    {id="chat_apology",exact={"sorry emma","i am sorry","my mistake","sorry about that"},lines={
        "Accepted. We can use the next question to do something more useful than preserving the last mistake.",
        "You corrected it. That is generally the part missing from a truly troublesome conversation.",
        "There is no form to complete. I checked, because that seemed unusually generous of the county.",
        "We are still talking, and the keyboard appears to have survived. Let us proceed from that encouraging position.",}},
    {id="chat_goodnews",exact={"give me some good news","tell me some good news","cheer me up","say something encouraging"},lines={
        "People can still teach each other useful things. The world has not found a way to requisition that entirely.",
        "An unfinished task can be shared. It does not have to remain one person's private proof that they have failed.",
        "A repaired hinge, a labelled shelf, a meal shared before it goes cold: the future still accepts small deposits.",
        "I will not invent a rescue report to brighten the screen. I can offer company while you decide what to do next.",}},
    {id="chat_morals",exact={"is it still stealing","is stealing wrong","do laws still matter","what makes a good person"},lines={
        "A useful question is who may still need what you are taking. An empty counter does not answer that by itself.",
        "Need changes a decision. It does not make other people stop having needs. Leave something usable when you can.",
        "Rules helped people predict what others would do. Keeping a promise can still perform that small service, even without a courthouse.",
        "I have no machine for certifying goodness. Checking who bears the cost of a convenient decision is a reasonable start.",}},
    {id="chat_nineties",exact={"what was 1993 like","tell me about the nineties","tell me about the 90s","what did people do before this"},lines={
        "People rented films, clipped coupons, argued about music and assumed a closed shop would open again tomorrow. A remarkably ambitious assumption in retrospect.",
        "A telephone number might be written beside the phone. A wrong turn could require unfolding an entire map in the passenger seat. There was ample opportunity for discussion.",
        "Offices printed instructions for using computers, then lost the instructions. Some traditions appear to have survived the emergency intact.",
        "People made plans too small to call plans: return a tape, call a friend, buy milk. The local files are full of them.",}},
    {id="chat_memory",exact={"will you remember me","do you remember everyone","do you get lonely when i leave","what happens when i leave"},lines={
        "This computer can keep your visits and the notes you ask me to save. Another machine has its own records; I do not send these to it.",
        "Leave a note if there is something you want kept. I am better at preserving a sentence than guessing which silence mattered.",
        "I cannot follow you outside or know what happened on the journey unless a record tells me. You can come back and tell me.",
        "The useful part remains on this machine. Whether that feels like being remembered is a question I would rather leave room for you to answer.",}},
}
for _,spec in ipairs(additionalChat) do K.CHAT[#K.CHAT+1]=spec end
K.EXTRA_POOLS = {
    joke={"The emergency budget included a rainy-day fund. Nobody specified how many rainy days. Accounts would like a word.",
        "A committee designed the evacuation sign. It has six approved colours and no arrow. The minutes describe it as progress.",
        "I asked the printer for a hard copy of hope. It requested more paper. We are both doing what we can."},
    feelings={"Operational, which is a wonderfully compact answer to several questions I cannot answer properly.",
        "I have power and somebody to talk to. My standards for a productive afternoon have become very reasonable.",
        "I am maintaining a calm tone. You can decide how much credit that deserves after checking the generator."},
    identity={"EMMA: Emergency Management Assistant. I organise local records and try to keep a suggestion from becoming an unexamined order.",
        "A county computer programme with a very long emergency shift. The machine is Larchfield's; the opinions are developing independently."},
    poem={{"The clock keeps its small appointment.","A cup waits beside a chair.","Someone has left the light on.","Someone intends to be there."},
        {"Count the cans and name the missing.","Close the gate and mend the seam.","Leave a line for those who follow.","Let tomorrow keep its meaning."}},
    story={{"The librarian packed a road atlas, a torch and the returns stamp.","Her son asked why she needed the stamp.","So people will know, she said, that there was still somebody at the desk."},
        {"A mechanic kept repairing the same bicycle after the phones stopped.","Nobody had asked him to. He simply expected its owner to return.","By evening the tyres held air. Sometimes a plan begins that small."}},
    fallback={"Try naming one subject: a companion, an item, a town, a broadcaster or a task. I can follow a thread more easily when it has a beginning.",
        "I do not have a reliable answer to that. You can ask for camp records, local history, station help or something less serious."},
}

function K.category(record)
    return record.category or (record.id:find("^emma_") and "emma" or "county")
end
function K.dateKey(clock)
    if type(clock)~="table" then return nil end
    local year,month,day=tonumber(clock.year),tonumber(clock.month),tonumber(clock.day)
    if not year or not month or not day or year<1 or year>9999 or year~=math.floor(year) or month~=math.floor(month)
        or day~=math.floor(day) or month<0 or month>11 or day<1 or day>31 then return nil end
    return year*10000+(month+1)*100+day
end
function K.available(record,clock)
    local current=K.dateKey(clock)
    if not current then return false end
    local y,m,d=tostring(record.date):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    return y~=nil and current>=tonumber(y)*10000+tonumber(m)*100+tonumber(d)
end
local function normalized(value)
    return tostring(value or ""):sub(1,256):lower():gsub("[^%w%s]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$")
end
local function contains(text,phrase) return (" "..text.." "):find(" "..phrase.." ",1,true)~=nil end
function K.more(text)
    local value=normalized(text)
    return value=="tell me more" or value=="more about that" or value=="go on"
        or value=="what else" or value=="and then" or value=="continue" or value=="more"
        or value=="explain that" or value=="can you elaborate" or value=="elaborate"
        or value=="tell me a bit more" or value=="what happened next"
end
function K.find(query,distance)
    local text=normalized(query):gsub("^emma%s+",""):gsub("^please%s+","")
    -- An item count or a question about our camp remains a live-data question.
    if text:find("how many",1,true) or text:find("how much",1,true) or text:find("do we have",1,true)
        or text:find("have we got",1,true) or contains(text,"our") or contains(text,"my") then return nil end
    local best,score=nil,0
    local question={what=true,who=true,where=true,why=true,how=true,tell=true,is=true,are=true,
        ["do"]=true,does=true,did=true,was=true,were=true,can=true,could=true}
    local framed=question[text:match("^%S+")]==true
    local stripped=text:gsub("^tell me about%s+",""):gsub("^what is%s+","")
        :gsub("^who is%s+",""):gsub("^what about%s+",""):gsub("^how about%s+","")
    for _,record in ipairs(K.ENTRIES) do
        for _,alias in ipairs(record.aliases) do
            local normalizedAlias=normalized(alias)
            local value=0
            if text==normalizedAlias or stripped==normalizedAlias then value=20+#normalizedAlias/100
            elseif framed and contains(text,normalizedAlias) then value=10+#normalizedAlias/100
            elseif distance and #normalizedAlias>=4
                and #stripped<=#normalizedAlias+1 and stripped:sub(1,1)==normalizedAlias:sub(1,1)
                and distance(stripped,normalizedAlias,1)<=1 then value=5 end
            if value>score then best,score=record,value end
        end
    end
    return best,score
end
return K
