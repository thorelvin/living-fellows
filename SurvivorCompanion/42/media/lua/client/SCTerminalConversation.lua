-- SPDX-License-Identifier: MIT
-- Read-only operating help and bounded, session-local conversation threads.
-- Store subjects, never native objects, live facts or executable requests.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalConversation = {}
local C = SC.TerminalConversation
C.MAX_TOPICS, C.MAX_HISTORY, C.MAX_AGE = 8, 16, 24
C.MAX_IDLE_MS = 600000
C.GUIDES, C.CHAT = {}, {}

local function guide(id, title, questions, first, more)
    C.GUIDES[#C.GUIDES+1]={id=id,title=title,questions=questions,pages={first,more}}
end

guide("camp", "Starting a camp",
    {"how do i start a camp","how do i set up a base","how do i make a base","how do i set camp core","where do i start a base"},
    {"Right-click the ground, then Living Fellows > Base life > Set camp core here. Mark storage and work areas, then assign residents to base duty.",
     "Start with food, clean water, medical supplies and tools. A camp is easier to run when its shelves mean what their labels say."},
    {"Use More > Base for the selected companion's job and the camp's policies. Storage management is at the bottom.",
     "Press Insert to inspect the marked layout. Rooms and floors still need usable routes between them."})
guide("storage", "Marking and removing storage",
    {"how do i mark storage","how do i unmark storage","how do i remove storage","how do i change storage","how does storage work"},
    {"Right-click a container inside camp and use Living Fellows > Base life to mark its storage category.",
     "To remove the marking, choose Unmark storage. The container and its contents remain where they are."},
    {"Camp workers use permitted marked supplies and respect reserves. A label is permission, not an instruction to manufacture its contents.",
     "Ask how many nails, how much food or shortages for current records. Unmarked shelves are not part of that count."})
guide("sorting", "Sorting floor and trash",
    {"how do i sort loot","how does sorting work","how do i make a sorting floor","where does trash go","why is loot on the floor"},
    {"Mark a Sorting floor inside camp and leave loot there. Residents on base duty carry useful items into the matching permitted storage.",
     "Mark a Trash pile separately. Missing or full destinations leave items waiting; General is not a substitute for every missing category."},
    {"Ask any problems to read actual blocked reasons and retry information. Make room or mark the missing destination before retrying.",
     "Reserved supplies, protected belongings and items nobody can carry are not ordinary loose loot."})
guide("jobs", "Assigning camp work",
    {"how do i assign jobs","how do i give someone a job","how do base jobs work","how do i change a job","how do i put someone on base duty"},
    {"Select the companion, open More > Base and choose their job at the top. They need base duty enabled to perform ordinary camp work.",
     "Ask who is best at first aid, carpentry or another recorded skill to compare the people currently at home."},
    {"Jobs still need tools, permitted materials, a usable route and safe conditions. Work outside at night follows the camp's night-work policy.",
     "Ask what is everyone doing for work records, or any problems for blocked work. I can read the queue; I cannot negotiate with a wall."})
guide("retry", "Paused and blocked work",
    {"why do jobs get blocked","how do i retry a job","how do i reset a stuck job","do blocked jobs retry","why is sorting blocked"},
    {"Blocked work usually needs supplies, storage space or a usable route. Many jobs pause and retry automatically; their recorded reason and countdown explain the current case.",
     "Ask any problems. To request a manual retry, use retry job followed by the job ID I report. I ask for confirmation."},
    {"A retry does not remove an obstruction or make a full shelf larger. Fixing the cause is generally less repetitive than arguing with the symptom.",
     "Uncertain cargo transfers need inspection rather than automatic replay. Missing cargo is not recreated."})
guide("watch", "Base Watch",
    {"how does base watch work","how do i use base watch","how do i keep camp loaded","can people work while i am away"},
    {"Base Watch keeps an indoor resident's camp view loaded while you travel, so the other residents can continue their ordinary work.",
     "Choose the watcher through the companion controls. Base Watch and expeditions share one companion view; use one at a time."},
    {"Keep the watcher indoors and the camp equipped for the jobs you expect to continue. Loaded does not mean supplied or safe.",
     "Radio contact still needs working radios and the right channel. A second view is not a second human player."})
guide("expeditions", "Planning an expedition",
    {"how do i send an expedition","how do expeditions work","how do i send a squad","how do i launch a mission","what expeditions can i send"},
    {"Assign one to four companions to a squad, open Expeditions, choose its leader and task, then review the mission before sending them.",
     "Scout, Search, Fish and Collect wood use real crew, equipment and cargo. You can plan from a camp computer with a fitted two-way radio too."},
    {"Set walking or driving, return time and combat style. Choose on map keeps the normal map's zoom and annotation controls.",
     "The crew brings home what it actually obtains and can carry. Arriving home and storing the cargo are separate events."})
guide("targets", "Choosing expedition targets",
    {"how do i choose a destination","how do i choose on map","how do i select an expedition target","how far can expeditions go","why can not i select that building"},
    {"Choose on map in the expedition planner, right-click a building, shore or woodland, then select the highlighted target and return to mission review.",
     "Map targets allow up to 1,000 tiles walking or 5,000 driving. Beyond 200 tiles, the destination must be visited or revealed by a read map."},
    {"Revealing map fog through a display setting does not grant exploration knowledge. Road distance may be longer than the straight distance shown.",
     "A map identifies a destination. Entrances, water, trees, danger and the actual route still need checking on arrival."})
guide("wood", "Collecting wood",
    {"how do i collect wood","how does wood collection work","how do i get logs","how do i send a logging expedition","why do they need an axe"},
    {"Choose Collect wood, walking or driving, and a log target. Preparation borrows a usable real axe from permitted camp storage.",
     "One cutter works while the crew hauls and protects them. A solo companion cuts and hauls when carrying room permits."},
    {"Logs must be physically picked up and carried or loaded. Full load has a ceiling of 256 verified logs, and cargo space can impose a lower limit.",
     "Delivery prefers permitted Log Yard, Construction, then General storage. A log yard arranges four-log stacks in rows."})
guide("fishing", "Fishing expeditions",
    {"how do i send them fishing","how does fishing work","how do i prepare a fishing trip","why does fishing need equipment"},
    {"Choose Fish nearby water and a shore. Preparation collects a usable fishing rod and bait from permitted camp supplies, waiting and retrying if equipment is missing.",
     "Crew with their own usable equipment can fish; the others provide protection. A possible mapped shore still needs suitable water on arrival."},
    {"Set the requested catch and return time before departure. Only fish actually caught at the selected site count.",
     "Bait, safety, time and carrying space can end the trip early. The catch still needs delivery into permitted home storage."})
guide("delivery", "Returned cargo",
    {"why is cargo pending","how do i unload expedition cargo","why did they return with nothing stored","how does delivery work","where do expedition supplies go"},
    {"Collected, carried and stored are different counts. Ask deliveries for returned cargo still awaiting permitted home storage.",
     "Full or inaccessible storage pauses delivery. Make room or correct access; the normal retry and manual Retry remain available."},
    {"The restock-and-resume-duty setting does not waive delivery. Borrowed tools still need returning too.",
     "A roadside fallback can leave cargo in a verified stopped car within camp work reach. If it is farther away, recovery is still required."})
guide("radio_reports", "Contacting an expedition",
    {"how do i contact the team","how do i recall an expedition","how do i get a radio report","why is expedition progress unknown","why will they not answer"},
    {"The operator and team need working, equipped radios on the same channel and within their native range. A fresh report requires a real return transmission.",
     "A fitted camp station can request progress, recall the crew and answer route decisions. Away does not mean I can see through the map."},
    {"Check power, radio condition, channel and range. Scanning away from the team frequency can miss a call.",
     "For a handheld recall, right-click the working radio and use the expedition return option when available."})
guide("taxi", "Markus's taxi",
    {"how do i call a taxi","how does the taxi work","how do i call markus","how do i call marcus","what does the taxi cost","why will the taxi not come"},
    {"Use a working two-way walkie-talkie and choose Markus's Taxi > Call for pickup. Stand near a usable road and read the booking message.",
     "Bring jewelry for the fare. Once aboard, choose a road destination on the map. A fitted computer station can use the same booking service."},
    {"A television is not a two-way radio. Its willingness to make noise does not establish a professional relationship with a taxi driver.",
     "If pickup is refused, the actual booking message is the useful evidence. I cannot promise an arrival merely because a road appears on a map."})
guide("rest", "Sleep and tiredness",
    {"why is my companion tired","how do companions sleep","how do i make them rest","why are they sitting","why do they not go to bed","why are they not sleeping"},
    {"Stamina and tiredness are separate readings on Status. Rest areas, usable beds, a reachable access tile and safe conditions matter when companions seek sleep.",
     "At camp, check the Rest marking and the route beside the bed. A room can contain a bed without providing a usable way into it."},
    {"Danger and active orders can interrupt rest. Ask about a named companion for its actual needs rather than treating every pause as exhaustion.",
     "The reading shows the need; it does not by itself identify which obstacle or order prevented sleep."})
guide("recruit", "Recruitment",
    {"how do i recruit someone","how do i recruit a companion","how do i get followers","why can not i recruit them","how many companions can i have"},
    {"Meet the survivor, select them and choose Recruit when it is offered. Talk and standing matter; not every stranger is available to join.",
     "Living Fellows supports up to 16 recruited companions. Special characters can have their own conditions before recruitment."},
    {"Households have their own needs and relationships. Treat a refusal as information about that survivor, not an invitation to convert another mod's actor.",
     "Use the companion panel and Talk for the choices currently offered. I do not replace their decision with a command."})
guide("orders", "Companion orders",
    {"how do i tell them to follow","how do i give orders","how do i make them stay","how do i stop a companion","how do i regroup"},
    {"Select the companion and use Orders, or right-click them for the available follow, stay, regroup and retreat controls.",
     "Home opens the companion panel. Groups and squad signals are on Squad; individual orders and combat style remain separate choices."},
    {"A companion may interrupt an order for immediate danger or survival needs. Status shows its current action and Last action problem.",
     "For a stuck actor, note the obstruction before using Regroup. The useful question is usually what stopped the route."})
guide("combat", "Combat orders",
    {"how do i change combat style","how do i stop them shooting","how do i make them use guns","how do combat orders work","why will they not shoot"},
    {"Use Orders and Loadout to inspect combat style, weapon preference, ammunition and carry load. Squad signals can call cease fire or fire when their conditions are met.",
     "A usable gun is not sufficient by itself: ammunition, a target, range, visibility and a clear firing lane still matter."},
    {"Companions avoid protected people in their firing lane and can retreat when outmatched. Close defense and quiet choices affect when they engage.",
     "Read the actual loadout and current action before changing orders. I cannot establish a missed shot's cause from a weapon's name alone."})
guide("medicine", "Medical help",
    {"how do i heal a companion","how do i send a medic","how do i treat wounds","why is health low","how do i check injuries"},
    {"Use Medical Check on the companion, or ask who is hurt from a camp computer. Visible wounds and bandage condition matter more than health percentage alone.",
     "Ask send medic to followed by their name. I propose an eligible helper and wait for your confirmation; supplies and a usable route are still required."},
    {"A helper already treating somebody else is not free for a second patient. Low health without a visible treatable wound may need time or another kind of care.",
     "Knox infection, ordinary illness and an infected wound are different problems. I do not turn a bandage into a cure."})
guide("water", "Camp water",
    {"how do i get drinking water","how do i provide water","how do i set up water storage","why will they not drink","is rain water safe"},
    {"Mark permitted Water storage and provide clean drinking water. Companions still need accessible supplies and carrying room.",
     "Treat the game's water safety label as authoritative. Collected water is not automatically clean merely because its container looks reassuring."},
    {"Ask how many water bottles to inspect recorded supplies, or check the companion's thirst and current action.",
     "If water is inaccessible, a larger inventory count does not solve the route. Storage permission and physical access both matter."})
guide("food", "Feeding the camp",
    {"how do i feed everyone","how do i store food","how do i set up a kitchen","why will they not eat","how do i stop food spoiling"},
    {"Mark food storage and keep usable meals or ingredients accessible. Regular food and Fresh food distinguish food that keeps from food that spoils.",
     "Ask how much food for recorded items, calories and an estimate for the people currently at home. The estimate is not a meal reservation."},
    {"Cooking needs its actual tools, ingredients and heat source. Refrigeration follows the game's real electricity supply.",
     "Keep water and food reachable. A beautifully organized locked pantry remains a locked pantry."})
guide("farming", "Camp farming",
    {"how do i start farming","how do i assign a farmer","how do i grow food","how does farming work"},
    {"Mark the appropriate camp work area, assign a Farmer on base duty and provide the tools and supplies required by the available farming jobs.",
     "Plants still use the game's growth and care rules. Assignment is not a substitute for seeds or water."},
    {"Inspect the Base job report for a missing tool, supply or route. Harvested food needs suitable permitted storage.",
     "If you want the current stock, ask about a crop by name rather than asking this operating note to inspect a field."})
guide("graves", "Burial and memorials",
    {"how do i bury the dead","how do i assign a gravekeeper","how do memorials work","what happens when a companion dies"},
    {"Use the camp's burial work and an assigned Gravekeeper with the required tools and a usable route. The job works with actual bodies.",
     "Companion death is permanent. Their belongings and any diary remain physical things to recover, not a replacement survivor waiting in a menu."},
    {"Memorial storage and ordinary burial areas have different purposes. Read the job's refusal if a body cannot be moved.",
     "Grief is part of the survivors' record. An empty bed is information the camp notices."})
guide("computer", "Using EMMA",
    {"how do i use this computer","how do i use emma","how do i open a computer","what can i ask emma","how do i talk to you"},
    {"Stand beside a powered desktop and choose Use computer. Tab switches chat and the numbered menu; Enter sends a question; Esc returns or logs off.",
     "Ask about people, marked supplies, jobs, power, weather, expeditions or local files. I also have jokes, stories and a modest tolerance for repetition."},
    {"Numbers choose entries while the menu is focused. In chat they remain ordinary text. Page Up, Page Down and the wheel read long replies.",
     "Try who is hurt, how many nails, any problems, what should I do or tell me about West Point."})
guide("offline", "Offline operation",
    {"are you connected to the internet","can you search the internet","can you browse the web","do you need wifi","are you a real ai","how do you answer questions"},
    {"This program runs entirely inside the game. No real internet connection, hosted language model, account or external service is involved.",
     "I match questions to supported subjects and read the camp records made available to this computer. The county-network language belongs to the fiction."},
    {"Local files are archived writing, not evidence that a distant place is currently safe. Unsupported questions receive a limitation instead of an invented reading.",
     "You may ask a shorter question or name the person, item or system you mean. Specificity is an excellent substitute for telepathy."})
guide("memory", "Conversation and notes",
    {"how does your memory work","how long do you remember","can you remember this conversation","what do you remember about this conversation","how do i save a note"},
    {"While this terminal session is open I keep a small recent-topic history. You can ask what were we talking about, go back to the previous topic, or check a subject again.",
     "Use remember followed by a note to save it on this computer. A brief logoff keeps the thread; ten idle real minutes or a world reload clears temporary conversation."},
    {"Brief thanks or acknowledgements do not erase the subject. Names and items are looked up again when you follow up; an old answer is not a fresh measurement.",
     "Forget that conversation clears the recent thread. Forget everything clears your saved notes. Factory reset is a separate confirmed operation."})
guide("password", "Password recovery",
    {"how do i hack a computer","how does password recovery work","how do i unlock this computer","what do the brackets do","why am i locked out"},
    {"Choose a candidate word. The feedback counts letters in the correct positions. Hidden bracket groups can remove a wrong candidate or restore attempts.",
     "Electrical skill helps. Running out of attempts locks recovery for one game hour; the same puzzle returns afterward with fresh attempts."},
    {"Moving or reopening a machine does not reroll the puzzle. A computer's password and its building's security password are separate protections.",
     "A successful recovery gives a small one-time Electrical XP award. Reading a help file does not count as a successful recovery, unfortunately."})
guide("files", "Reading old files",
    {"how do i read old files","who owned this computer","where are the personal files","what are outbreak fragments","are these files true"},
    {"Open Personal files for the machine's assigned former owner, or County files and EMMA for reference material and archived accounts.",
     "The personal entries are original July 1993 stories matched to rooms and businesses. They travel with their computer."},
    {"Outbreak fragments are unverified fictional local accounts. Dated reports appear when your save reaches their date.",
     "An old diary is evidence of what its writer recorded. It does not certify a current route, open shop or living witness."})
guide("radio", "Fitting a station radio",
    {"how do i mount a radio","how do i install a walkie talkie","how do i make an expedition station","what does the antenna do"},
    {"Use Local services > Computer upgrades. A usable two-way walkie-talkie, Electrical 2, a screwdriver, one wire and two electronics scrap are required.",
     "The fitted handset powers the station's radio functions and adds the antenna to the frame. It retains its identity, channel and presets."},
    {"The computer powers its mounted receiver without recharging the handset's original battery. Native radio range still applies.",
     "Ask open radio for LARCH/WAVE, or use the local-services menu. Removing the handset returns the actual mounted item."})
guide("scanner", "Finding broadcasts",
    {"how does the scanner work","how do i find broadcasts","how do i scan channels","why is the radio silent","what do the radio bars mean"},
    {"Open radio, then Scanner. Scan presets listens through saved presets; Band sweep steps across the mounted handset's tuning range.",
     "Actual reception holds the channel. Choose Stay on this channel or Continue scanning. Silence during a short listen does not prove there is no station."},
    {"The visual follows receive activity; it is not a spectrum analyzer. The notebook retains received text and the heard-stations list records real reception at this PC.",
     "A single handset listens to one channel. Scanning during a mission needs confirmation because it can miss the team's calls."})
guide("ups", "Computer battery backup",
    {"how do i install battery backup","how does the ups work","how long does the computer battery last","can i use a computer without power"},
    {"Install a UPS through Computer upgrades with Electrical 4, a screwdriver, one wire, four scrap and a charged car battery.",
     "A full healthy battery supplies about six game hours of active PC and radio use. Poor condition shortens that time."},
    {"The UPS supplies this computer, not the building, refrigerator or door motors. Remove its actual battery to recharge normally.",
     "Mounted parts add weight and move with the computer. The unpowered computer's context menu still offers hardware removal."})
guide("controls", "Connecting building equipment",
    {"how do i connect local controls","how do i control a building","how do i connect equipment","how do i authorize building security"},
    {"Choose Local services > Connect local controls. Bring Electrical 2, a screwdriver, one wire and two electronics scrap.",
     "Recover the building's own password or use its matching physical key. Unlocking this computer does not authorize every door in the building."},
    {"Open Equipment after connecting. Discovery reads loaded equipment in bounded slices, so large buildings can need another visit to the list.",
     "Physical relays, motors and sensors have their own installation requirements. No extra power mod is required."})
guide("doors", "Doors and shutters",
    {"how do i open doors remotely","how do i control a garage door","how do i roll up shutters","why will the door not open","how do i fit a door motor"},
    {"Connect and authorize the building through Local services, then inspect the opening in Equipment. Remote movement needs a fitted, powered motor.",
     "Grouped native garage doors move together. People, bodies, vehicles, barricades and lost actuator power can stop movement."},
    {"A motor installation needs Electrical 4 and its listed parts. The PC's UPS does not supply the actuator.",
     "A return-garage routine waits for the actual returned car inside, stopped with its engine off, and a clear doorway before closure."})
guide("lights", "Lights and routines",
    {"how do i control lights","how do circuits work","how do i turn lights on at night","how do i enable lockdown","how do automatic routines work"},
    {"Connect local controls, fit the required lighting relays and use Equipment to name devices or group lights. Constructed floodlights need their own usable supply.",
     "Routines are opt-in. Night lighting switches selected lights at 20:00 and 06:00; lockdown leaves obstructed steps pending."},
    {"Moving or disconnecting the authorizing computer suspends its routines. Start with one named light group so the result is easy to inspect.",
     "Generator supply and lighting relays are supported. Individual fridge/freezer switching is not available."})
guide("generator", "Generator service",
    {"how do i refuel a generator","how do i start a generator","how do i repair a generator","how do i fit a remote starter","why will the generator not start"},
    {"Ask refuel generator to propose the normal camp job. Connected local services also offer start, stop and repair using a suitable available companion.",
     "Fuel, condition, parts, a usable route and the native startup result still apply. Read the service's actual refusal before retrying."},
    {"A fitted remote starter needs Electrical 4, its listed components and a real removable car battery. Each start attempt uses one percent of its charge.",
     "Stopping the real generator removes its supply normally. A PC backup battery does not keep the camp's appliances powered."})
guide("security", "Alarms and sensors",
    {"how do i control alarms","how do i silence an alarm","how do i install motion sensors","how do i use the siren","how do i use the pa"},
    {"Authorize the building, then use its security services. Silence affects this building's active alarm, not every alarm in the world.",
     "Fitted contacts and motion sensors add local detections. A siren or evacuation announcement makes real noise and attracts infected."},
    {"History is bounded. A past detection is not proof that somebody is standing in the same place now.",
     "Read the installation page for the chosen device's skill and components. The computer cannot attach a motion sensor by describing it persuasively."})
guide("diaries", "Companion diaries",
    {"how do diaries work","can i read a companion diary","where are their diaries","what do companions remember"},
    {"Some companions keep physical diaries and remember shared events, relationships and promises. Their books remain with their belongings if they die.",
     "Use Talk to learn what a companion is willing to tell you. My camp report is not a transcription of their private thoughts."},
    {"Turning diary features off does not erase existing books. A physical diary can be kept, moved or lost like other belongings.",
     "I can discuss the system without claiming to have read a particular person's private entry."})
guide("strangers", "Households and Strange Folk",
    {"what are strange folk","when do strange folk appear","how do i meet strangers","how do households work","how do i trade with survivors"},
    {"Households trade, offer work and remember their standing with you. Strange Folk are authored encounters with their own requests and conditions.",
     "Strange Folk can begin from the second day; an eligible character is selected randomly. Suitable locations and the encounter schedule still matter."},
    {"Read the offered conversation and objective rather than assuming every stranger wants recruitment. Some radio rescues need an actual two-way reply.",
     "Current household and quest menus hold the available choices. This help file does not reveal undiscovered encounters."})
guide("support", "Finding a useful diagnostic",
    {"how do i report a bug","where are the logs","how do i get a support report","why is the companion stuck","what is last action problem"},
    {"Open More > Support for the diagnostic report. Status shows Current action and Last action problem for the selected companion.",
     "For a report, include the game and mod versions, what happened, the Support report and a relevant screenshot or log excerpt."},
    {"The obstruction, last command and timing are more useful than resetting the actor repeatedly. Remove private information before posting logs.",
     "I can interpret recorded job reasons, but I do not have unrestricted access to your computer's files."})

local function chat(id, exact, lines)
    C.CHAT[#C.CHAT+1]={id="chat_"..id,exact=exact,lines=lines}
end
chat("home",{"what makes a home","does this place feel like home","can we build a life here"},{
    "A home is where somebody notices that you are late. A roof and stored water make that arrangement more sustainable.",
    "Start with a dry bed and a place for the kettle. Civilization has repeatedly made worse opening proposals.",
    "Give people useful work and something worth returning to. You can install the second shelf after that."})
chat("silence",{"why is it so quiet","i hate the silence","say something","can we sit quietly"},{
    "We can sit quietly. I do not consider every unfilled second a software defect.",
    "There used to be traffic between those gaps. People complained about it with remarkable dedication.",
    "I am here. You need not produce a useful question to justify sitting down."})
chat("anger",{"i am angry","i am frustrated","i hate all of this","nothing is going right"},{
    "Then choose one problem small enough to finish. Anger is excellent at identifying unfairness and less reliable at organizing a tool shelf.",
    "You may be angry without making your next decision quickly. The county has already demonstrated the limitations of that combination.",
    "Name the thing that failed. We can inspect a job, a supply count or a person's needs without solving the entire emergency at once."})
chat("guilt",{"i feel guilty","i should have saved them","it was my fault","i let everyone down"},{
    "You know what happened afterward. That does not mean you possessed that information when you made the decision.",
    "I cannot acquit you from a keyboard. I can suggest feeding the people who are still here before you hold another hearing against yourself.",
    "If there is something to repair, name it. If there is only someone to miss, you do not have to turn that into a task."})
chat("hope",{"is there any hope","do we have a future","can things get better","why keep trying"},{
    "You are making plans beyond the next hour. I would count that as evidence, with the usual limitations on forecasting.",
    "Improvement is often embarrassingly ordinary: clean water, fewer wounds, somebody returning on time. It is still improvement.",
    "The old county could print a promise faster than it could keep one. I suggest beginning with a promise small enough to keep."})
chat("tired_operator",{"i am exhausted","i can not keep doing this","i need a break","i am so tired"},{
    "Then a break belongs in the plan. Being the last person to stop working does not make a human maintenance-free.",
    "Check immediate danger, drink, eat and find somewhere safe to rest. I can keep a note; I cannot sleep on your behalf.",
    "You are allowed to stop before you become another job requiring medical supplies."})
chat("rain_memory",{"do you like rain","what do you think about rain","what does rain remind you of"},{
    "Rain made the old office smell of wet coats and overheated carpet. I can preserve the record without recommending the carpet.",
    "I appreciate any weather that makes people check their water arrangements before the taps stop being cooperative.",
    "For current conditions, ask weather. For a philosophical objection to damp socks, I have no opposing argument."})
chat("seasons",{"what is your favourite season","what is your favorite season","do you like winter","do you like summer"},{
    "The one in which people prepare for the next one. An unpopular answer in a tourism brochure.",
    "Summer makes every power supply feel personally accused. Winter requires its own inventory of regrets.",
    "I favour weather that permits a dry return journey and ordinary sleep. My preferences have become rather specific."})
chat("art",{"do you like art","what is your favourite painting","what is your favorite painting","is art still important"},{
    "Yes. An inventory tells you what somebody kept. A picture occasionally tells you why.",
    "A wall can hold something other than a work schedule. This was true before the emergency and remains a defensible policy.",
    "People drew things before they had reliable plumbing. I see no reason to reverse the order now."})
chat("books",{"do you like books","recommend a book","what should i read","what is your favourite book","what is your favorite book"},{
    "Read something practical while there is light, then something unnecessary before sleep. You are preserving a person as well as a tool set.",
    "I can offer local files or county reference material. I will not claim to have a complete library merely because the filing system is ambitious.",
    "A book whose next page does not begin with EMERGENCY would provide a useful change of pace."})
chat("humans",{"what do you think of humans","do you like people","are humans good","why do people fight"},{
    "People invent rationing forms and then give away their own supper. A single statistical description loses useful detail.",
    "My records contain cruelty, cooperation and a surprising number of complaints about parking. Often from the same office.",
    "Ask about a person and I can check their readings. Ask about humanity and I must use a considerably less reliable filing cabinet."})
chat("honesty",{"can you be wrong","do you make mistakes","why should i believe you","what if you are wrong"},{
    "I can be wrong. A missing record, an ambiguous name or a misunderstood question is sufficient. You should be suspicious of a system that denies this.",
    "Ask what I mean, name the subject or request a fresh reading. Confidence is an attractive font, not a source.",
    "A count from marked storage is a count from marked storage. It is not everything in every drawer in the county."})
chat("choice",{"what would you do","if you were me","would you leave","should i stay or go"},{
    "I would inspect supplies, people's condition and a way back before choosing. Fortunately, I can help with the first two without possessing legs.",
    "For a practical next step, ask advice. For permission to abandon every difficult decision, my department never received that authority.",
    "A route home is part of an outward journey. People tend to rediscover this after the fuel warning."})
chat("names",{"why are you called emma","what does emma stand for","do you like your name","can i give you a nickname"},{
    "Emergency Management Assistant. The acronym was approved before anybody asked whether I could manage this particular emergency.",
    "EMMA fits on the screen and is easier to shout across an office than the procurement description.",
    "You may call me what you like. The program and the header will remain EMMA; bureaucracy is occasionally useful for identity protection."})
chat("coffee_break",{"how was your day","what did you do today","anything interesting today","what is on your mind"},{
    "I answered questions and attempted to keep unverified information out of the answers. The latter activity is less popular than it deserves.",
    "Mostly records. If you want today's actual camp situation, ask status; I would rather check than furnish a charming invented afternoon.",
    "The possibility of a complete handover note. I am trying to maintain realistic ambitions."})
chat("stars",{"do you like the stars","what is beyond the sky","do you believe in aliens","are we alone in the universe"},{
    "I have no verified visitors from another world on record. Several visitors from the next office were sufficiently confusing.",
    "There is a considerable amount of sky beyond the county's jurisdiction. I find that a reasonable arrangement.",
    "I cannot settle the universe from this terminal. I can keep you company while it declines to explain itself."})
chat("promises",{"will you protect us","promise we will be safe","promise you will not leave","can you promise anything"},{
    "I can promise to distinguish a reading from a guess. I cannot promise that a dark road is safe because you need it to be.",
    "While this machine has power and you are using it, I will answer what I can. That is the promise the hardware permits.",
    "I would prefer an honest small promise to a large official reassurance. The county has supplied comparative evidence."})
chat("change_subject",{"let us talk about something else","change the subject","new topic","ask me something"},{
    "We could discuss an old county file, a place you remember, a practical camp problem or something pleasantly unnecessary. Choose whichever requires the least courage today.",
    "Would you prefer a story, a joke, local history or a look at the camp records? I can make several kinds of conversation without making several kinds of promise.",
    "All right. Tell me the subject, and we can leave the previous one in its folder."})

C.EXTRA_POOLS={
    joke={
        "The last office meeting was postponed until further notice. Against considerable odds, somebody finally kept a scheduling promise.",
        "I found a form for reporting missing forms. Its absence would have created a genuinely impressive administrative problem.",
        "The county promised a paperless office. Several departments are now also roofless, which was not in the proposal.",
        "A generator, a filing cabinet and a survivor enter a garage. Only one of them admits how much maintenance it needs.",
        "Our suggestion box is empty. Either morale has improved or everyone has discovered a more direct application for a hammer.",
        "The office refrigerator said PROPERTY OF MANAGEMENT. Apparently management considered yoghurt a strategic asset.",
        "I was asked to think outside the box. The box contains my power supply, so the performance review became rather technical.",
        "The old emergency plan had an appendix for unexpected events. The appendix was blank. I admire the honesty, if not the preparation.",
    },
    story={
        {"A clerk kept a spare umbrella under her desk for a colleague who always forgot his.",
         "On the last afternoon she left two umbrellas by the door and wrote a note saying neither had to be returned.",
         "It was the first useful policy change that office had made in years."},
        {"A man repaired the same porch step every spring. His neighbour called it a waste of decent nails.",
         "When the roads closed, three households began using that porch as a place to count who had come home.",
         "The step held. He was unbearably pleased about this."},
        {"The school secretary left the lost-property cupboard unlocked before leaving.",
         "Inside were six small coats, a lunch tin and a torch that worked when you held the switch sideways.",
         "She had put fresh batteries beside it. Nobody had asked her to make an inventory."},
        {"A radio operator wrote the date on every page, even when there was no answer to record.",
         "The final entry was not a transmission. It said that the kettle had boiled and he would try once more after tea.",
         "I do not have the next page. I prefer not to invent one."},
    },
    poem={
        {"A cup beside a darkened screen,", "A coat upon a chair,", "The smallest things announce a life", "And ask us to take care."},
        {"The road forgets the names of feet.", "The house remembers keys.", "We carry what we cannot count", "And count the things we need."},
        {"Leave one light for the late return,", "One place beside the door.", "We have no map of what comes next.", "We had no map before."},
        {"Rain on the roof,", "A pencil marking who came home.", "Keep the pencil dry."},
    },
}

C.GUIDE_WORDS={
    camp={"base","camp"},storage={"storage","containers","shelves","unmark"},
    sorting={"sorting","sort","trash","loot"},jobs={"jobs","job","duty","base duty"},
    retry={"blocked","retry","reset job"},watch={"base watch","watcher","keep loaded"},
    expeditions={"expedition","expeditions","squad","mission"},targets={"destination","map","targets"},
    wood={"logs","wood","logging","trees"},fishing={"fishing","fish","rod","bait"},
    delivery={"cargo","unload","delivery"},radio_reports={"recall","radio report","contact team"},
    taxi={"taxi","markus","marcus"},rest={"sleep","rest","tired","bed"},recruit={"recruit","recruitment","followers"},
    orders={"follow","stay","regroup","orders"},combat={"shoot","shooting","guns","combat","fight"},
    medicine={"heal","wound","wounds","medic","bandages"},water={"water","drink"},food={"food","meals","eat","kitchen"},
    farming={"farm","farming","plant","crops"},graves={"bury","burial","grave","dead"},
    computer={"emma","computer","terminal"},offline={"internet","llm","online","wifi"},
    memory={"remember","notes","memory"},password={"password","hack","hacking","unlock"},
    files={"files","lore"},radio={"mount radio","handset","walkie talkie"},scanner={"scan","scanner","broadcasts","frequencies"},
    ups={"backup","ups","battery"},controls={"connect","equipment","building controls"},
    doors={"doors","door","garage","shutter"},lights={"lights","light","circuit","circuits","lockdown"},
    generator={"generator","refuel","starter"},security={"alarm","sensor","siren","security"},
    diaries={"diaries","diary"},strangers={"strange folk","household","households","strangers"},support={"support","bug","diagnostic"},
}
C.EXPLAIN={
    storage={"This count covers accessible marked camp storage, not every unmarked cupboard or a guaranteed crafting recipe. Tell me a required quantity if you want a comparison."},
    food={"Days of food are an estimate from recorded calories and the people currently at camp. Away crew and supplies outside the marked audit are not silently added."},
    power={"These are the current available supply readings. Fuel, generator condition, connection and a usable service route can each affect what happens next."},
    weather={"This is the current weather reading, not a promise about conditions along a distant expedition route."},
    time={"The date and day count come from this save's game clock. Archived reports remain limited by their own dates."},
    blocked={"The recorded reason is the starting point. Automatic retry timing and manual-only recovery differ by job; a retry does not recreate uncertain cargo."},
    jobs={"An assignment still needs a ready worker, supplies, storage space and a usable route. Ask any problems for the actual blocked-job reasons."},
    zombies={"This is a nearby loaded-area reading around the terminal, not a survey of a town, a guarantee of safety or an invented remote report."},
    person={"I can report the recorded condition and activity. Those readings do not prove why a person stopped or replace an examination of a wound or blocked route."},
    expedition={"Observed progress and received reports are different sources. Collected, carried and stored remain separate, and old radio information is not a fresh sighting."},
    math={"I evaluated the arithmetic you supplied. A computed quantity is not proof that the camp has that many physical items."},
}

function C.clean(value, limit)
    return tostring(value or ""):gsub("[^ -~]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$"):sub(1,limit or 160)
end
local function words(text)
    return C.clean(text):lower():gsub("[^%w%s]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$")
end
function C.guide(id)
    for _,record in ipairs(C.GUIDES) do if record.id==id then return record end end
end
function C.findGuide(text, tokenize, distance)
    local function normalize(value)
        local out=table.concat(tokenize(value)," "):gsub("^emma%s+",""):gsub("^please%s+","")
        return out:gsub("^could you tell me%s+",""):gsub("^can you tell me%s+","")
            :gsub("^would you tell me%s+",""):gsub("^how can [iw]e?%s+","how do i ")
            :gsub("^how do we%s+","how do i "):gsub("^how to%s+","how do i ")
            :gsub("%s+please$",""):gsub("%s+emma$","")
    end
    local query=normalize(text)
    if not C.questionIndex then
        C.questionIndex,C.questionForms={},{}
        for _,record in ipairs(C.GUIDES) do
            for _,question in ipairs(record.questions) do
                local candidate=normalize(question)
                C.questionIndex[candidate]=record
                C.questionForms[#C.questionForms+1]={text=candidate,record=record}
            end
        end
    end
    if C.questionIndex[query] then return C.questionIndex[query] end
    if distance and #query>=12 then
        local found
        local frame=query:match("^(%S+%s+%S+%s+%S+)")
        for _,form in ipairs(C.questionForms) do
            local candidate,record=form.text,form.record
            if frame and frame==candidate:match("^(%S+%s+%S+%s+%S+)") and math.abs(#query-#candidate)<=1
                and distance(query,candidate,1)<=1 then
                if found and found~=record then return nil end
                found=record
            end
        end
        if found then return found end
    end
    -- Flexible wording is limited to instructional questions. Current counts,
    -- named-person readings and commands must keep their ordinary live lanes.
    if query:find("^how do i ") or query:find("^where do i ") or query:find("^where can i ") then
        local best,score,tied=nil,0,false
        local padded=" "..query.." "
        for _,record in ipairs(C.GUIDES) do
            local value=0
            for _,term in ipairs(C.GUIDE_WORDS[record.id] or {}) do
                if padded:find(" "..term.." ",1,true) then value=value+1+(term:find(" ",1,true) and 1 or 0) end
            end
            if value>score then best,score,tied=record,value,false
            elseif value>0 and value==score then tied=true end
        end
        if not tied then return best end
    end
end

function C.state(session)
    session.conversation=session.conversation or {topics={},history={}}
    local state=session.conversation
    local now=C.clock(session)
    if now and state.lastAt and (now-state.lastAt>C.MAX_IDLE_MS or now<state.lastAt) then
        state.topics,state.history={},{}
        -- Consume expiry before parsing the next question. record() also
        -- calls state(), and must not erase a freshly prepared clarification
        -- or lore reference during that same response.
        state.lastAt=nil
        for _,key in ipairs({"person","personId","item","itemText","referenceId","referencesSeen","pending","personChoices","intent"}) do
            session.context[key]=nil
        end
    end
    for i=#state.topics,1,-1 do
        local topic=state.topics[i]
        if (session.turns or 0)-topic.turn>C.MAX_AGE or now and topic.at
            and (now-topic.at>C.MAX_IDLE_MS or now<topic.at) then table.remove(state.topics,i) end
    end
    return state
end
function C.clock(session)
    if type(session.nowMs)~="function" then return nil end
    local ok,value=pcall(session.nowMs)
    local now=ok and tonumber(value)
    if now and now==now and now>=0 and now<1e15 then return now end
end
function C.latest(session, kinds)
    for _,topic in ipairs(C.state(session).topics) do
        if not kinds or kinds[topic.kind] then return topic end
    end
end
function C.copyWords(values)
    local out={}
    for i=1,math.min(6,#(values or {})) do out[i]=C.clean(values[i],32) end
    return out
end
local NEUTRAL={thanks=true,ack=true,hello=true,sorry=true,compliment=true,empty=true,["repeat"]=true,
    fallback=true,did_you_mean=true,did_you_mean_no=true,yes=true,no=true,clear=true,exit=true,
    request=true,factory_reset=true,factory_reset_help=true,conversation_history=true,
    conversation_forget=true,conversation_missing=true,clarify_person=true,chat_apology=true,chat_patience=true,
    remember=true,forget=true,callme=true,whoami=true,recall=true}
function C.neutral(intent) return NEUTRAL[intent]==true end
function C.record(session, raw, reply, slots)
    local state=C.state(session)
    state.lastAt=C.clock(session)
    if reply.intent~="empty" and reply.intent~="repeat" and reply.intent~="conversation_forget" then
        state.history[#state.history+1]={question=C.clean(raw),intent=reply.intent}
        while #state.history>C.MAX_HISTORY do table.remove(state.history,1) end
    end
    if reply.error or C.neutral(reply.intent) then return end
    local topic={intent=reply.intent,kind="data",turn=session.turns or 0,label=reply.intent,at=state.lastAt}
    local intent=reply.intent
    if intent=="person" and slots.person then
        topic.kind,topic.id,topic.label="person",slots.person.id,C.clean(slots.person.name,80)
        topic.aspect=slots.aspect
    elseif intent=="people_hurt" or intent=="people_list" or intent=="people_mood" then
        topic.kind,topic.people="people",reply.subjects or {}
        if #topic.people==1 then
            topic.kind,topic.id,topic.label,topic.intent="person",topic.people[1].id,topic.people[1].name,"person"
        end
    elseif intent=="storage" or intent=="food" then
        topic.kind="item"
        topic.item=C.copyWords(intent=="food" and {"food"} or slots.item)
        topic.itemText=C.copyWords(intent=="food" and {"food"} or slots.itemText or slots.item)
        topic.label=table.concat(topic.itemText," ")
        topic.required=slots.required
    elseif intent=="math" then
        topic.kind,topic.expression,topic.value="math",slots.expression,slots.value
        topic.label=slots.expression or "arithmetic"
    elseif intent=="guide" then
        topic.kind,topic.id="guide",slots.guideId
        topic.page=math.min(#(C.guide(topic.id) or {pages={}}).pages+1,slots.page or 1)
        topic.label=(C.guide(topic.id) or {}).title or "Operating help"
    elseif intent=="lore" then
        if not session.context.referenceId then return end
        topic.kind,topic.id="lore",session.context.referenceId
        topic.label=topic.id
    elseif intent=="skills" then topic.query=slots.query topic.label=slots.query or "skills"
    elseif intent:find("^chat_") or reply.category=="chat" then topic.kind="chat" end
    local key=topic.kind..":"..tostring(topic.id or topic.kind=="item" and table.concat(topic.item," ")
        or topic.query or topic.expression or topic.intent)
    topic.key=key
    for i=#state.topics,1,-1 do if state.topics[i].key==key then table.remove(state.topics,i) end end
    table.insert(state.topics,1,topic)
    while #state.topics>C.MAX_TOPICS do table.remove(state.topics) end
end
function C.forget(session)
    session.conversation={topics={},history={}}
    session.context={}
end
function C.aspect(text)
    local value=" "..words(text).." "
    if value:find(" skills ",1,true) or value:find(" good at ",1,true) or value:find(" best at ",1,true) then return "skills" end
    if value:find(" mood ",1,true) or value:find(" morale ",1,true) or value:find(" stressed ",1,true)
        or value:find(" happy ",1,true) or value:find(" feeling ",1,true) then return "mood" end
    if value:find(" tired ",1,true) or value:find(" thirsty ",1,true) or value:find(" hungry ",1,true)
        or value:find(" need ",1,true) or value:find(" needs ",1,true) or value:find(" stamina ",1,true) then return "needs" end
end
function C.quantity(text)
    local source=C.clean(text)
    if source:find("%d%.%d") or source:find("for%s*%-") or source:find("need%s*%-") then return nil end
    for _=1,3 do source=source:gsub("(%d),(%d%d%d)%f[%D]","%1%2") end
    if source:find("%d,%d") then return nil end
    local value=words(source)
    local n=value:match("enough.-%f[%w](%d+)%f[%W]") or value:match("for%s+(%d+)%f[%W]")
        or value:match("need%s+(%d+)%f[%W]") or value:match("do we have%s+(%d+)%f[%W]")
    n=tonumber(n)
    if n and n>=1 and n<=1000000 then return math.floor(n) end
end
function C.topicTurn(topic)
    if not topic then return end
    if topic.kind=="guide" then return "guide",{guideId=topic.id,page=topic.page} end
    if topic.kind=="person" then return "person_reference",{id=topic.id,name=topic.label,aspect=topic.aspect} end
    if topic.kind=="math" then return "math",{expression=topic.expression,value=topic.value} end
    if topic.kind=="item" then return topic.intent,{item=C.copyWords(topic.item),itemText=C.copyWords(topic.itemText),required=topic.required} end
    if topic.kind=="lore" then return "lore",{referenceId=topic.id} end
    return topic.intent,{query=topic.query}
end
function C.meta(session, text)
    local value=words(text)
    if value=="what were we talking about" or value=="what did we talk about" or value=="what was my last question"
        or value=="what did i ask you" or value=="recap our conversation" then return "conversation_history",{} end
    if value=="forget that conversation" or value=="forget this conversation" or value=="forget this topic"
        or value=="forget that" or value=="start a new conversation" then return "conversation_forget",{} end
    local topic=C.latest(session)
    if topic and topic.kind=="math" and type(topic.value)=="number" then
        local number,operation
        local raw=C.clean(text):lower():gsub("^and%s+",""):gsub("[?!]+$","")
        if raw=="double it" or raw=="double that" then number,operation=2,"*"
        elseif raw=="halve it" or raw=="half of that" then number,operation=2,"/"
        else
            number=tonumber(raw:match("^multiply .- by ([%d%.%-]+)$") or raw:match("^times ([%d%.%-]+)$"))
            if number then operation="*" else
                number=tonumber(raw:match("^divide .- by ([%d%.%-]+)$"))
                if number then operation="/" else
                    number=tonumber(raw:match("^plus ([%d%.%-]+)$") or raw:match("^add ([%d%.%-]+)$"))
                    if number then operation="+" else number=tonumber(raw:match("^minus ([%d%.%-]+)$")) operation="-" end
                end
            end
        end
        if number and number==number and math.abs(number)<1e15 then
            local result=operation=="*" and topic.value*number or operation=="/" and topic.value/number
                or operation=="+" and topic.value+number or topic.value-number
            if result~=result or math.abs(result)==math.huge then result=nil end
            return "math",{expression=tostring(topic.value).." "..operation.." "..tostring(number),value=result}
        end
    end
    local back=value:match("^go back to%s+(.+)$") or value:match("^back to%s+(.+)$")
        or value:match("^return to%s+(.+)$")
    if back then
        local topics=C.state(session).topics
        if back=="the previous topic" or back=="previous topic" or back=="the last topic" then
            if topics[2] then return C.topicTurn(topics[2]) end
            return "conversation_missing",{query="the previous topic"}
        end
        for _,topic in ipairs(topics) do
            local label=words(topic.label)
            if label==back or (" "..label.." "):find(" "..back.." ",1,true) then return C.topicTurn(topic) end
        end
        return "conversation_missing",{query=back}
    end
end
function C.more(text)
    local value=words(text)
    return value=="more" or value=="tell me more" or value=="go on" or value=="what else"
        or value=="explain that" or value=="why" or value=="why is that" or value=="what do you mean"
        or value=="can you elaborate" or value=="elaborate" or value=="more about that"
        or value=="another one" or value=="one more" or value=="another"
        or value=="what does it mean" or value=="what about that" or value=="explain it"
end
function C.refresh(text)
    local value=words(text)
    return value=="and now" or value=="what about now" or value=="check again" or value=="any change"
        or value=="has that changed" or value=="same question" or value=="ask that again"
end
return C
