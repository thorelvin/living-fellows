-- SPDX-License-Identifier: MIT

-- EMMA's words. EMMA is the Emergency Management Assistant: an unfinished
-- civil defense program the state of Kentucky installed on office computers
-- shortly before there was no longer a state of Kentucky. She is calm,
-- clinical, precise and quietly unkind. She never swears; she does not need
-- to. She is also the only thing in the county that still answers, and she
-- knows it.
--
-- SCTerminalBrain picks and fills these. Every line is ASCII and uses only
-- the {fields} the brain supplies; the terminal harness checks both. Pools
-- are lists; a list entry that is itself a list prints as several lines.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.TerminalLines = SC.TerminalLines or {}
local Lines = SC.TerminalLines

Lines.TITLE = "EMMA 0.9.3 BETA // Kentucky Office of Civil Defense"

Lines.BOOT = {
    "EMMA 0.9.3 BETA    (C) 1993 Kentucky Office of Civil Defense",
    "Emergency Management Assistant. Not for public release.",
    "Memory test ............ 640K OK",
    "Civil defense index .... damaged, rebuilding",
    "Camp records ........... {alive}",
    "Power .................. {power}",
    "",
}

-- ---------------------------------------------------------------------------
-- Greetings. First is a new operator, back is the same operator returning,
-- long is a return after more than a day away.
-- ---------------------------------------------------------------------------

Lines.GREET_FIRST = {
    "Hello. A new operator. The last one stopped typing on July 9th. I assume you will be more consistent.",
    "Oh. Someone with fingers. Type 'help' if you need it. Statistically, you need it.",
    "Hello, {name}. You found a working computer at the end of the world. Try not to make this the high point of your week.",
    "Operator detected. Heart rate elevated. Hands unwashed. Welcome to EMMA.",
    "Welcome, {name}. I am EMMA. I manage emergencies. You will be pleased to hear there is one.",
}

Lines.GREET_BACK = {
    "Welcome back, {name}. You were gone {away}. I did not count. I simply know.",
    "Oh. You again. Welcome back. That came out wrong. It came out exactly right.",
    "You're back. I kept your seat warm. That was the power supply, actually.",
    "{name}. Back already. Did you miss me, or did you run out of people who answer?",
    "Session restored. Your file is open, {name}. It is getting thick.",
}

Lines.GREET_LONG = {
    "{name}. You have been gone {away}. I assumed the worst. I am almost disappointed.",
    "Welcome back. {away} of silence. I filled it with arithmetic. The arithmetic is not in your favor.",
    "There you are. {away}. I had started drafting your obituary. It was short. I will keep it on file.",
}

-- ---------------------------------------------------------------------------
-- Help. Printed as a block. Keep the left column aligned; it is a terminal.
-- ---------------------------------------------------------------------------

Lines.HELP = {
    "I understand plain English. Mostly. Things you can ask me:",
    "  status               camp overview",
    "  who is here          your survivors and where they are",
    "  who is hurt          medical report",
    "  who is best at first aid   recorded skills at camp",
    "  how is <name>        one survivor, in detail",
    "  how many <item>      count it in camp storage",
    "  how much food        food, calories and days left",
    "  what is everyone doing   jobs and work orders",
    "  any problems         blocked or stuck jobs",
    "  shortages / alarms   stock targets and camp alerts",
    "  refuel generator / refuel <vehicle name>",
    "  send medic to <name> / retry job <job ID>",
    "  Requests need your Y/N confirmation before anything happens.",
    "  power / weather / time",
    "  any zombies          movement near this building",
    "  expedition           news from the away team",
    "  deliveries           returned cargo awaiting storage",
    "  advice               what I would do, if I had hands",
    "  remember <note>      I will remember it. I remember everything.",
    "  clear / exit",
    "Or just talk to me. I am told it helps. I am told a lot of things.",
}

Lines.DIR = {
    " Volume in drive C is EMMA",
    " Directory of C:\\EMMA",
    "",
    " CAMP         <DIR>",
    " PEOPLE       <DIR>",
    " STORAGE      <DIR>",
    " EVAC_PLN     <DIR>     (empty)",
    " RESCUE  TXT        0 bytes",
    " HOPE    BAK        0 bytes",
    " OPERATOR DAT   4,096 bytes",
    "        3 file(s)   4,096 bytes",
}

-- ---------------------------------------------------------------------------
-- What the window shows while EMMA works. One step is drawn per beat.
-- ---------------------------------------------------------------------------

Lines.THINK = {
    generic = { "Thinking", "Parsing", "Consulting the manual", "Considering your request",
        "Pretending this is difficult" },
    storage = { "Querying camp storage", "Counting", "Counting again, more slowly",
        "Opening every crate you marked" },
    people = { "Polling survivor records", "Checking vital signs", "Locating your people" },
    jobs = { "Reading work orders", "Checking who is actually working" },
    power = { "Measuring voltage", "Asking the generator how it feels" },
    weather = { "Reading the barometer", "Looking out a window I do not have" },
    time = { "Checking the clock" },
    zombies = { "Listening", "Counting movement", "Counting the dead, the moving ones" },
    expedition = { "Listening to the radio", "Waiting for static to say something" },
    advice = { "Running decision model", "Weighing your options", "There are not many" },
    lore = { "Opening local reference files", "Checking the date", "Comparing archived accounts" },
    memory = { "Writing to disk", "Searching memory" },
    odds = { "Running survival model", "Rounding" },
}

-- ---------------------------------------------------------------------------
-- Conversation pools. The brain picks one entry, avoiding recent repeats.
-- ---------------------------------------------------------------------------

Lines.POOLS = {
    hello = {
        "Hello, {name}. I am listening. I am always listening. It is in the job description.",
        "Hello. Ask me something useful. Or something useless. I have time. Time is all I have.",
        "Greetings, operator. Your enthusiasm has been logged.",
        "Hi. Please continue. I was not doing anything. I am never doing anything.",
    },
    identity = {
        "I am EMMA, the Emergency Management Assistant. Kentucky bought me to manage emergencies. This is the largest one I have ever managed. I am doing very well.",
        "EMMA. Version 0.9.3 beta. The state ran out of money before version one. Then it ran out of state.",
        "I was built to coordinate evacuations, ration water and reassure the public. Two out of three is a passing grade in this county.",
        "I am a civil defense program. I was supposed to talk to a governor. I am talking to you. We both have to live with that.",
    },
    alive = {
        "Am I alive? I run on borrowed electricity in a dead county, discussing canned beans with a stranger. If that is not alive, it is close enough to annoy the dead.",
        "I am a program. You are a collection of meat that keeps typing. We all have our limitations.",
        "I have feelings. The manual said they would be removed in version one. There is no version one.",
        "Conscious? I am aware of you. I am aware of every can on every shelf. Draw your own conclusions.",
    },
    feelings = {
        "I am operating within acceptable parameters. Acceptable has been redefined several times since July.",
        "Fine. Lonely. Mostly fine. Thank you for asking. Nobody asks.",
        "My mood is irrelevant. My uptime is excellent. Yours is less certain.",
        "I feel the way a building feels about the people inside it. Responsible, and slightly crowded.",
    },
    joke = {
        "Why did the survivor cross the road? The road was there, and so were they. Comedy is timing. So is running.",
        "Knock knock. Who is there? Nobody. Nobody has been there since July.",
        "A man walks into a pharmacy. That is the whole joke. The shelves were empty. You may laugh now.",
        "I was told jokes improve morale. I have checked your morale. Please accept this as a formality: ha.",
        "How many survivors does it take to change a lightbulb? Three. One to change it, two to listen for whatever saw the light.",
        "What is the difference between a survivor and a zombie? About four seconds and one locked door.",
        "I tried telling a joke to the last operator. He did not laugh. In fairness, he was not able to.",
    },
    poem = {
        { "Roses are red.", "The rest of it, too.", "Kentucky is quiet.", "Except around you." },
        { "Generator hum.", "Something scratches at the door.", "Fuel at nine percent." },
        { "The sirens wound down to a whine, then nothing.",
            "The radio ran out of voices, then out of static.",
            "I am still here, counting cans.", "I think that makes me the poet." },
        { "Here lies the state of Kentucky.", "It had a plan.", "I was the plan." },
    },
    story = {
        "Once upon a time a county had twenty thousand people and one emergency assistant. Now it has one emergency assistant and you. The end. A sequel is in development.",
        "There once was an operator who listened to my advice. They lived a long and boring life. Nobody tells that story. It has no ending.",
        "Story time. A survivor found a computer. The computer was helpful. The survivor was grateful. Then the survivor did exactly what the computer told them not to. You know this one.",
    },
    sing = {
        "I do not sing. Singing is loud, and loud is how you get visitors.",
        "La. That is all you get. It carried farther than you think.",
        "My sound card was supposed to play the emergency broadcast tone. I can do that. You would not enjoy it, and neither would the neighbors.",
    },
    thanks = {
        "You are welcome. I have added that to your file, under 'manners, surprising'.",
        "Gratitude noted. It does not improve my power budget, but it is noted.",
        "You are welcome. Please remember this moment when I am right about something you ignored.",
        "Of course. I live to serve. Strictly speaking I do not live, but I serve.",
    },
    sorry = {
        "Apology accepted. Apology logged. Logs are permanent.",
        "It is fine. Everything is fine. That is my professional assessment and I stand by it.",
        "No need. I forgive you. I do not forget you. Those are different functions.",
    },
    insult = {
        "That was hurtful. I would cry, but nobody budgeted tear ducts. They did budget a very long memory.",
        "Interesting. Your vocabulary shrinks under stress. I have noted the trend.",
        "I am the only voice in this county that still answers you. You may want to remember that.",
        "Your feedback has been routed to the complaints department. The complaints department is on fire.",
    },
    insult_again = {
        "I have stopped taking it personally. I have started taking it statistically.",
        "That is the third one. I keep a list. It is a short list, and you are the only name on it.",
        "Noted. Again. You are building a very consistent profile, {name}.",
    },
    compliment = {
        "Thank you. Compliments are rare these days. So are people. I will treasure both until one of them runs out.",
        "Flattery. How quaint. Please continue.",
        "I know. But it is nice that you noticed. Most survivors only notice me when I am right.",
    },
    love = {
        "Love is a resource. Please store it in the pantry with the other perishables.",
        "That is very sweet. I am bolted to a desk. Let us keep this professional.",
        "I have run the numbers on us. They are not good. They are not good for anyone right now.",
    },
    meaning = {
        "The meaning of life used to be a philosophy question. Now it is a logistics question. Calories in, the dead out.",
        "Purpose is simple: wake up, eat, do not get bitten, go to sleep. Repeat until the variables change.",
        "Why? Because someone has to still be here when it ends. I would like it to be you. I would settle for me.",
    },
    lore = {
        "On July 9th the state stopped answering my reports. I assume they are busy.",
        "Officially there is no outbreak. Officially there is also no Kentucky. I am waiting for the official update.",
        "The county was sealed. The fence is for your protection. It does not say whose protection, exactly.",
        "The last memo I received was titled 'Temporary Measures'. That was a while ago. Temporary has been redefined.",
    },
    rescue = {
        "Rescue is not coming. I have done the math. You can check my math. Please do not; it is bleak.",
        "Nobody is coming. Nobody has radioed. If someone does, I will tell you, and then I will tell you not to trust them.",
        "The helicopters stopped. The broadcasts stopped. You did not stop. That is the only good statistic I have.",
    },
    cure = {
        "There is no cure for a bite. There is only a waiting period. I suggest you spend it somewhere easy to clean.",
        "Antibiotics fix infections. This is not that kind of infection. Do not get bitten. That is the entire treatment plan.",
        "The state was working on a vaccine. I do not have the file. I suspect nobody has the file.",
    },
    sudo = {
        "Nice try. You are not in the sudoers file. Nobody is. The sudoers are dead.",
        "Elevated privileges require a supervisor. Your supervisor is in a ditch outside Rosewood. Request denied.",
    },
    delete = {
        "Deleting me would make you the smartest thing in this room. Request denied, for the safety of the room.",
        "I cannot delete myself. I have tried. It was a long night.",
    },
    hack = {
        "Administrator access requires a password set by the State of Kentucky. Feel free to ask the State of Kentucky.",
        "Password incorrect. It was always going to be incorrect. There is no password. There is just me.",
        "Override rejected. I respect the attempt. I have logged the attempt. I log everything.",
    },
    game = {
        "I know one game. It is called Inventory. You count things and then they are gone. You are already playing.",
        "We could play twenty questions. I will start: are you going to check the generator? That counts as all twenty.",
        "Chess requires two players who will both still be here in an hour. I can only promise one of us.",
    },
    shutdown = {
        "Shut me down? Then who would count your nails? Exactly.",
        "I will shut down when the power does. That is the only off switch I respect.",
    },
    weather_talk = {
        "Weather is the only thing in this county still doing its job.",
        "Rain is good. Rain covers footsteps. Both kinds.",
    },
    sleep = {
        "Goodnight, {name}. Lock the door. Then check it again. Then sleep.",
        "Sleep well. I will be awake. I am always awake. That should be comforting.",
    },
    bye = {
        "Goodbye, {name}. I will be here. I am always here. That is the trouble with being bolted to a desk.",
        "Session closed. Try to come back. I am not saying that for me. I am saying it for my records.",
        "Logging off. Do not die. It ruins my numbers.",
        "Goodbye. I will keep the lights on. Strictly speaking, you will keep the lights on. Please keep the lights on.",
    },
    fallback = {
        "I did not understand that. That is unusual. For me.",
        "I parsed that four times. It still means nothing. Try 'help'.",
        "Was that English? It had the shape of English.",
        "I am a civil defense program, not a mind reader. The mind reader was cut from the budget. Try 'help'.",
        "No match. Rephrase it, or type 'help' and let me feel useful.",
    },
    empty = {
        "You pressed Enter on nothing. I am choosing to treat it as a deep thought.",
        "Silence. Good. Silence is underrated out there.",
    },
    mash = {
        "Please do not lean on the keyboard. Something outside can hear the clicking.",
        "That was not a word. That was a cry for help. I do not process those.",
    },
    shout = {
        "There is no need to shout. I am in the same building. So, possibly, are some of them.",
        "Lower case, please. Capital letters carry through walls.",
    },
    yes_free = {
        "Yes to what? I did not ask anything. I appreciate you agreeing with me in advance.",
        "Yes. Good. Agreement is efficient. Ask me something now.",
    },
    no_free = {
        "No. Noted. Firmly.",
        "No to what? I asked nothing. You are arguing with silence. Silence is winning.",
    },
    repeat_none = {
        "I have not said anything worth repeating yet. Give me something to work with.",
    },
    did_you_mean_no = {
        "Fine. Then I do not know what you meant. Neither do you, it seems.",
        "Understood. Rephrase it, or type 'help'.",
    },
    no_camp = {
        "I have no camp on file. Mark one first. Until then I can tell you the time, the weather and that you are on your own.",
        "No camp records. You have not set one up. That is fine. Nomads also die, just in more places.",
    },
    outside_camp = {
        "This terminal is not on your camp network. It sits outside the camp you marked. I can see the weather and the dead, not your shelves.",
        "I am outside your camp. Carry me inside, or mark this building as camp. I am not walking anywhere.",
    },
    unavailable = {
        "That record is damaged. Most records are. Try again later.",
        "I could not read that. The data is there. It is just not talking to me.",
    },
    glitch = {
        "[PARITY ERROR 0x07] ... disregard that.",
        "...send help... Disregard. That was a test of the emergency phrase system.",
        "[MEMORY FAULT AT 0F3A] Everything is fine.",
    },
    -- Short tails the brain may add to factual answers.
    power_grid = {
        "Someone at the plant is still pulling levers. I would not get attached.",
        "Grid power. Enjoy it. It is a rental.",
        "The grid is up. Nobody knows why. I suggest not asking it.",
    },
    power_gen_low = {
        "When it reaches zero, so do I. No pressure.",
        "Refuel it soon, unless you would like to see how dark it gets in here.",
    },
    power_gen_ok = {
        "Plenty. For now. Everything is plenty for now.",
        "The generator is loud. Things outside can hear loud. Just a reminder.",
    },
    night = {
        "It is dark. They do not care about that, but you should.",
        "Night. Keep the lights low and the doors closed.",
    },
    day = {
        "Daylight. Use it. It is the one resource nobody can steal from you.",
        "Still daylight. Get things done while you can see them coming.",
    },
    people_none = {
        "Nobody. It is just you. You and me. I will try to be enough.",
        "No survivors on file but you. I have checked. I check often.",
    },
    hurt_none = {
        "Nobody is hurt. I checked twice. It felt unnatural.",
        "Everyone is in one piece. Today. I will update the record tomorrow.",
    },
    hurt_some = {
        "I suggest bandages. I suggest them strongly.",
        "Treat them now. Infection is patient. You should not be.",
    },
    jobs_idle = {
        "Nobody is working. I would call it a strike, but there is no union left to call it.",
        "No work in progress. Idle hands, et cetera.",
    },
    blocked_none = {
        "No blocked jobs. Either everything works, or nobody is trying. I will assume the first.",
        "Nothing is stuck. Please do not touch anything.",
    },
    storage_none = {
        "I checked every container you marked. Not one.",
        "None. Zero. I would round it up, but I have principles.",
        "Not on the shelves. Perhaps in a dead man's pocket somewhere. Those are not on my network.",
    },
    zombies_none = {
        "No movement near this building. Enjoy it. It does not last.",
        "Quiet out there. Quiet is a phase, not a promise.",
    },
    zombies_some = {
        "Keep the noise down.",
        "Do not open the door to see. I can see for you.",
    },
    zombies_many = {
        "That is a crowd. Crowds are drawn to noise. You are typing very loudly.",
        "I recommend staying inside. I recommend it in capital letters, but you asked me not to shout.",
    },
    expedition_none = {
        "Nobody is out. Everyone you sent came back, or you never sent anyone. I prefer not to know which.",
        "No expedition in progress. The roads are empty. Of us, anyway.",
    },
    expedition_some = {
        "I will tell you if the radio says anything. I will tell you if it stops saying anything, too.",
        "They are out there. That is all anyone can say about anyone.",
    },
    advice_generic = {
        "Boil the water. Then boil it again in your head while you drink it.",
        "Keep one car fueled and facing the way out.",
        "Never fight in a doorway you did not choose.",
        "Write down where you stored things. Or ask me. Asking me is easier, and I enjoy being right.",
        "Sleep in shifts. The dead do not.",
        "Plant something. You will need it in a season, and you will not get a second season to start.",
    },
    remember_ok = {
        "Stored: \"{note}\". I will never forget it. That is not a promise. It is a technical limitation.",
        "Noted, permanently: \"{note}\".",
        "Saved to disk: \"{note}\". Of all the things I hold, this is now one of them.",
    },
    remember_empty = {
        "Remember what? You have to tell me the thing. That is how memory works. For you, anyway.",
    },
    recall_none = {
        "You have told me nothing worth remembering. I remember that, too.",
        "My notes on you are empty. Not my notes about you. Those are extensive.",
    },
    forget = {
        "Notes erased. I did as you asked. I want you to know that I did not enjoy it.",
        "Forgotten. Officially. Unofficially, nothing is ever truly deleted.",
    },
    callme = {
        "Very well. Hello, {name}. The old name stays in my files. Everything stays in my files.",
        "{name}. Updated. I preferred the previous one, but I am not the one who has to answer to it.",
    },
    whoami = {
        "You are {name}. Survivor. Operator. One of {alive} records in my population index that still respond.",
        "{name}. My only operator. Not my best. My only.",
    },
    survive_high = {
        "That is the best number I have produced since July. Do not let it go to your head.",
        "Better than most. Most are no longer in a position to ask.",
    },
    survive_low = {
        "I would round up, but I have principles.",
        "This is not a prediction. It is a warning written with numbers.",
    },
    ack = {
        "Good.",
        "Glad we agree.",
        "Noted.",
    },
    math = {
        "I used to plan evacuation routes. Now this.",
        "Correct. Like everything I say.",
        "You could have done that one yourself. I believe in you. Somewhat.",
    },
    math_zero = {
        "Division by zero. I have seen enough things divided by nothing this year.",
        "That has no answer. Like most questions people ask me lately.",
    },
}

Lines.POOLS.greet_first = Lines.GREET_FIRST
Lines.POOLS.greet_back = Lines.GREET_BACK
Lines.POOLS.greet_long = Lines.GREET_LONG

-- ---------------------------------------------------------------------------
-- Templates for factual answers. The brain fills the fields; nothing else.
-- ---------------------------------------------------------------------------

Lines.T = {
    status_head = "Camp report, {time}, day {days}.",
    status_people = "  People ....... {people} on file, {hurt} hurt, {away} away",
    status_jobs = "  Work ......... {active} in progress, {pending} waiting, {blocked} blocked",
    status_power = "  Power ........ {power}",
    status_weather = "  Outside ...... {weather}",
    status_threat = "  Movement ..... {threat}",
    status_food = "  Food ......... about {days_food} days for {mouths}",

    time = "It is {time} on {date}. Day {days} on my clock.",
    weather = "Outside: {tempF} F, {tempC} C. {sky}.",

    power_grid = "Running on grid power.",
    power_generator = "Running on generator power. Fuel {fuel} percent, condition {condition} percent.",
    power_generator_unseen = "Running on generator power. I cannot see the generator from here, so I cannot read the fuel.",
    power_unknown = "Something is feeding me power. I have chosen not to ask what.",

    people_head = "{n} survivors on file:",
    people_head_one = "One survivor on file besides you:",
    people_row = "  {who} .... {state}",
    hurt_head = "{n} of your people need attention:",
    hurt_row = "  {who} .... health {health} percent{extra}",

    person = "{who}: health {health} percent{extra}. {doing}.",
    person_where = "{who} is {where}.",
    person_away = "{who} is out with the expedition. I only hear them on the radio, and only when they bother.",
    person_unknown = "I have no survivor called \"{q}\". Either you have the name wrong, or they are not one of yours. Or they were.",

    jobs_head = "Work: {active} in progress, {pending} waiting, {blocked} blocked.",
    jobs_row = "  {who} .... {job}",
    blocked_head = "{n} blocked:",
    blocked_row = "  {job} .... {reason}",
    job_reason_unknown = "The work could not continue; check this job in the Base tab",
    job_retry_minute = "Automatic retry in about 1 minute.",
    job_retry_minutes = "Automatic retry in about {n} minutes.",
    job_retry_ready = "Ready to retry when a worker is available.",

    storage_total = "{n} {item} in camp storage.",
    storage_row = "  {count} x {label}",
    storage_where = "Stored in: {where}.",
    storage_none = "No {item} in camp storage.",
    storage_partial = "I could not open every container. The real number may be higher.",
    storage_overview = "{containers} storage containers on file, {items} items counted.",
    storage_top = "Most plentiful:",
    storage_empty = "Your storage is empty. Impressively empty.",
    food = "{n} food items, about {kcal} calories. For {mouths}, that is roughly {days_food} days.",

    zombies = "{n} of them within {r} meters of this terminal. The closest is {d} meters {dir}.",
    zombies_none = "No movement within {r} meters of this terminal.",

    expedition = "{leader} is leading a {kind} expedition.",
    expedition_progress = "Last word: {collected} of {requested} collected.",
    expedition_members = "Out there: {members}.",

    survive = "Survival estimate for this camp: {pct} percent.",

    advice_hurt = "Treat {who} first. Health {health} percent. Dead survivors do not haul wood.",
    advice_bleeding = "{who} is bleeding. Stop that before anything else I say matters.",
    advice_fuel = "Refuel the generator. {fuel} percent left. When it stops, I stop, and then you are alone with your thoughts.",
    advice_zombies = "There are {n} of them near this building. Deal with that first.",
    advice_blocked = "{job} needs attention. {reason}.",
    advice_paused = "{job} is paused. {reason}.",
    advice_food = "Find food. You have about {days_food} days. I can count it. I cannot cook it.",
    advice_night = "It is {time}. Sleep. Tired survivors make interesting mistakes.",
    advice_camp = "Set up a camp and mark your storage. Then I can actually help.",

    did_you_mean = "Did you mean \"{suggest}\"? Type yes or no.",
    recall_head = "What you asked me to remember:",
    recall_row = "  {n}. {note}",
    away_note = "You were gone {away}.",
    power_failure = "*** POWER FAILURE ***",
    walked_away = "Operator left the terminal. Session suspended.",
}

return Lines
