-- SPDX-License-Identifier: MIT

-- Lines for expeditions and work orders. Short, cold and dry: people doing
-- grim work in a quiet county, who still make the odd joke. Every rough word
-- has a clean twin for the profanity-off setting. SCWorkVoice decides when
-- any of this is said; this file only holds the words.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.WorkVoiceLines = SC.WorkVoiceLines or {}
local Lines = SC.WorkVoiceLines

-- ---------------------------------------------------------------------------
-- Action chat. One topic per moment; voice and mood rows add to common.
-- ---------------------------------------------------------------------------

Lines.POOLS = {
    ["voice.expedition.drive_out"] = {
        common = {
            "Engine's warm. That's the only warm thing out here.",
            "Doors locked, windows up. Let's go see what's left.",
            "Mind the ditches. The county's full of them, and of people in them.",
            "Radio off. Nobody's broadcasting anything we want to hear.",
            "Go slow past the church. Something always sits on those steps.",
            "Smells like old cigarettes in here. Whoever smoked them isn't coming back.",
            "Every mile of this road belongs to somebody dead.",
            { "If you hit one, don't brake. Just drive like hell.",
                clean = "If you hit one, don't brake. Just keep driving." },
            "Gray sky, gray road. At least the colors match.",
            "Nobody wave at anyone. Nobody waves anymore.",
        },
        brave = { "Let them chase the car. They never win.",
            "Faster. I want to be there before my nerve catches up." },
        cautious = { "Keep it under forty. Noise carries farther than you think.",
            "Watch the side roads. That's where they wait." },
        caring = { "Belts on, all of you. I mean it.",
            "Everyone comfortable? Good. Nobody gets left in a ditch today." },
        practical = { "Half a tank. Enough to get there and argue about getting back.",
            "Map's on the dash. Second left after the burned barn." },
        stressed = { "Just drive. Don't talk. Just drive." },
        low = { "Same roads. Fewer people. Every week, fewer." },
    },
    ["voice.expedition.drive_home"] = {
        common = {
            "Home, then. Whatever we still mean by that.",
            "Heater on. My hands stopped being mine an hour ago.",
            "Nobody look back. There's nothing back there we want.",
            "Same road home. Watch it anyway. It changes when you're not looking.",
            "If the engine dies now, I'm walking. Not waiting.",
            { "Drive. I've seen enough of this shit for one day.",
                clean = "Drive. I've seen enough of this for one day." },
            "Count the turns. A dozen more and we're behind a wall.",
            "Get us home before dark. I won't do this road blind.",
            "Quiet ride. That's the best kind now.",
        },
        brave = { "Good run. Let them come looking for it.",
            "Out and back with everyone breathing. I'll take that." },
        cautious = { "Lights off till the last bend. Habit.",
            "Slow at the bridge. It's where I'd wait, if I were them." },
        caring = { "Nearly there. Everyone's still breathing. Keep it that way.",
            "Rest your eyes if you can. I'll watch the road." },
        practical = { "Fuel's holding. We'll make it with a little to spare.",
            "Unload first, sleep after. Nobody argue." },
        low = { "Another day traded for a trunk of things." },
    },
    ["voice.expedition.park_site"] = {
        common = {
            "This is it. Engine off. Listen first.",
            "Leave the keys where we can find them in a hurry.",
            "Park facing out. If we leave, we leave fast.",
            "Quiet. Give it a minute. Let the place show us what's awake.",
            "Close the doors soft. They hear doors.",
            { "If it goes bad, back to the car like hell.",
                clean = "If it goes bad, back to the car, fast." },
            "Nobody's been here in weeks. Or somebody wants us to think so.",
            "Car stays. We go on foot from here.",
        },
        brave = { "I'll go first. I always do." },
        cautious = { "Check the windows before we cross the yard." },
        caring = { "Stay where I can see you. Every one of you." },
        practical = { "We work, we load, we leave. No sightseeing." },
    },
    ["voice.expedition.wood_arrive"] = {
        common = {
            "Good stand of trees. Nobody's touched it since July.",
            "Straight trunks. We start here.",
            "Listen to that. No birds. Work quiet.",
            "Plenty of wood, not much daylight. Let's waste neither.",
            "Woods are always darker than they look from the road.",
            "Every tree here is older than all of us put together.",
            { "Trees, mud and cold. Hell of a place to earn a fire.",
                clean = "Trees, mud and cold. Some place to earn a fire." },
            "Take the tall ones near the path. Short carry, short trouble.",
            "Axes out. Let's make some noise and hope nothing hears it.",
        },
        brave = { "Point me at the biggest one. I'll have it down by noon." },
        cautious = { "Keep the road in sight. Woods swallow people." },
        caring = { "Take turns with the axe. Nobody wears themselves out." },
        practical = { "Fell, cut, carry. Same as last time." },
        low = { "Chopping wood at the end of the world. Grandfather would laugh." },
    },
    ["voice.expedition.near_home"] = {
        common = {
            "There's the camp. Still standing.",
            "Smoke over the trees. Ours, I hope.",
            "Almost home. Don't relax yet. This is where people get careless.",
            "I can see the fence. Never thought a fence could look this good.",
            "Nearly there. Somebody put the kettle on.",
            { "Home. Or the closest damn thing to it.",
                clean = "Home. Or the closest thing to it." },
            "Last stretch. Eyes on the treeline.",
            "Light in a window. Somebody waited up for us.",
        },
        brave = { "See? I told you we'd make it." },
        cautious = { "Slow down. Let them see it's us before we walk in." },
        caring = { "Almost back. They'll want to see all our faces." },
        practical = { "Home soon. Unload first, sleep after." },
    },
    ["voice.expedition.turn_home.done"] = {
        common = {
            "That's enough. We head back.",
            "We got what we came for. Don't push our luck.",
            "Pack it up. Home, while the road still likes us.",
            "Done here. Nobody gets greedy.",
            { "That's the job. Let's get the hell out of here.",
                clean = "That's the job. Let's get out of here." },
            "Good. Now the hard part. Getting it home.",
        },
        brave = { "Job's done. Told you it'd be easy." },
        cautious = { "We go now, while it's still quiet." },
    },
    ["voice.expedition.turn_home.empty"] = {
        common = {
            "Nothing here worth the walk. We go back.",
            "Picked clean. Somebody beat us to it.",
            "Dead end. The place gave us nothing.",
            { "All this way for nothing. Damn this county.",
                clean = "All this way for nothing. Blast this county." },
            "We tried. It isn't here. Turning back.",
            "Whatever was here left before we did.",
        },
        low = { "Of course it was empty. Everything is." },
        practical = { "No point staying. We try elsewhere another day." },
    },
    ["voice.expedition.turn_home.full"] = {
        common = {
            "Can't carry another thing. Back we go.",
            "Bags are full. My back's fuller.",
            "No more room. Anything else stays for the next fool.",
            { "We're loaded to hell. Turning back.",
                clean = "We're loaded to the brim. Turning back." },
            "That's all we can carry. Let's not drop it on the way.",
        },
        practical = { "At capacity. Heading home with what we've got." },
    },
    ["voice.expedition.turn_home.time"] = {
        common = {
            "Getting late. We go now or we go in the dark.",
            "Clock's run out. Home.",
            "The light's going. Nobody wants this road at night.",
            "Time's up. Whatever's left can wait for another day.",
            "We said we'd be back by now. Let's keep our word.",
        },
        caring = { "They'll be worried at camp. Let's not make them wait." },
    },
    ["voice.expedition.turn_home.night"] = {
        common = {
            "Dark's coming. Woods at night are not for us.",
            "Can't see the trees anymore. We stop.",
            "No work after dusk. That's how people stop coming back.",
            "Sun's down. Whatever's out there wakes up hungry.",
            "Pack up before the dark gets ideas.",
        },
        cautious = { "Night. We go. Now, while we can still see the path." },
    },
    ["voice.expedition.turn_home.danger"] = {
        common = {
            "Too many of them. We leave. Now.",
            "Something's wrong out here. We go back.",
            { "Back. Back to the car. Don't argue, damn it.",
                clean = "Back. Back to the car. Don't argue, now." },
            "Not today. Nobody dies for firewood.",
            "We're done. I want everyone breathing when we get home.",
            { "Hell no. Turn around. All of you.",
                clean = "No way. Turn around. All of you." },
        },
        brave = { "We'll come back for it. With more of us." },
        caring = { "Stay close to me. We're going home." },
    },
    ["voice.expedition.turn_home.spent"] = {
        common = {
            "Arms are dead. Axe is dull. We go home.",
            "I've got nothing left. Neither has the axe.",
            "We're spent. Better home tired than not home at all.",
            "That's all the work in me today.",
        },
        practical = { "Tools are worn out. So are we. Back to camp." },
    },
    ["voice.expedition.turn_home.radio"] = {
        common = {
            "Word from camp. They want us back.",
            "Radio says home. We go home.",
            "Orders came. Wrap it up.",
            "Camp's calling us in. Nobody argue with the radio.",
            "Heard you. Turning back.",
        },
    },
    ["voice.expedition.turn_home.generic"] = {
        common = {
            "Turning back. Stay together.",
            "That's it. Home.",
            "We head back now. Same way we came.",
            "Let's go home before the county changes its mind.",
        },
    },

    -- Wood expeditions.
    ["voice.wood.chop"] = {
        common = {
            "Here we go. Stand clear.",
            "One more. Then another one.",
            "Swing, breathe, swing. Don't think about anything else.",
            "This one's been waiting for me.",
            "Wood doesn't scream. That's what I like about it.",
            { "Come on, you stubborn bastard. Down.",
                clean = "Come on, you stubborn thing. Down." },
            "My father cut wood every winter. I never watched. I should have.",
            "The noise carries. Keep an eye on the treeline.",
            "Hard wood, cold hands. Honest work, at least.",
            "If I stop, I start thinking. So I don't stop.",
        },
        brave = { "Watch this. Three swings." },
        cautious = { "Somebody watch my back while I'm busy." },
        caring = { "Stand back, all of you. I don't want it landing on anyone." },
        practical = { "Notch on the fall side. Then the back cut." },
        stressed = { "Every swing, I hear them coming. Keep watching." },
        low = { "Chop it, carry it, burn it. Repeat until dead." },
    },
    ["voice.wood.timber"] = {
        common = {
            "Timber!",
            "Tree down. Mind your feet.",
            "There she goes.",
            "Down. Now the carrying, which is the worse part.",
            "One less tree. The forest won't miss it.",
            "Heard that crash? So did everything else. Stay sharp.",
            { "Down she goes. Hell of a sound.",
                clean = "Down she goes. What a sound." },
            "Seventy years standing. Four minutes to fall.",
            "Clear the logs before anything comes to see what fell.",
        },
        brave = { "Ha! Next." },
        cautious = { "Down. Everyone freeze a second. Listen." },
        caring = { "Everyone clear? Good. Good." },
        practical = { "Tree's down. Logs on the ground. Collect them." },
        low = { "It fell like everything falls now. Quick and quiet." },
    },
    ["voice.wood.haul"] = {
        common = {
            "Got one. Heavy as sin.",
            "This log's mine. Carrying it.",
            "My shoulders remember being younger.",
            "Wood's wet. Weighs twice what it should.",
            { "This log weighs a damn ton.",
                clean = "This log weighs a ton." },
            "Picking it up. Don't watch, it isn't graceful.",
            "Back to the pile with this one.",
            "Splinters in my hands. Proof I was here.",
        },
        practical = { "One log, two hands. Moving." },
        caring = { "I've got this one. Rest a second." },
    },
    ["voice.wood.load"] = {
        common = {
            "In the trunk. Next.",
            "Trunk's filling. Slowly. Like everything.",
            "Logs stacked. The car smells like a forest now.",
            "Loaded. Don't worry about the paint. The owner's dead.",
            "That's another armful in.",
            { "Shove it in. Close the damn lid.",
                clean = "Shove it in. Close the lid." },
            "Car's sitting lower. Good sign.",
        },
        practical = { "Loaded. Counting them as we go." },
        brave = { "Easy. Bring me more." },
    },
    ["voice.wood.full"] = {
        common = {
            "That's it. Not one more log fits.",
            "Trunk's full. The springs are crying.",
            "Full. We could tie some to the roof, but we won't.",
            { "Full to hell. Time to go.",
                clean = "Full to the brim. Time to go." },
            "No more room. The rest stays for the next poor soul.",
            "Can't carry another. My back has filed a complaint.",
        },
        practical = { "No room left. Heading back." },
        cautious = { "Full. Good. Let's not linger now." },
    },
    ["voice.wood.rest"] = {
        common = {
            "Need a minute. Arms aren't listening.",
            "Give me a breath. Just one.",
            "Catching my wind. Watch the trees for me.",
            "Hands are shaking. Not from fear. Mostly.",
            "Sit a moment. The wood isn't going anywhere.",
            { "My arms are shot to hell.",
                clean = "My arms are shot." },
            "Old axe, tired hands. Both need a rest.",
        },
        brave = { "Thirty seconds. Then I'm back." },
        caring = { "Rest when you need to. Me too, apparently." },
    },
    ["voice.wood.wait"] = {
        common = {
            "Waiting on the axe. Shout when a tree's down.",
            "I'll carry. Somebody else swing.",
            "Standing here like a hired mourner. Call me when there's wood.",
            "Waiting. Keeping watch while I'm at it.",
            "Nothing to carry yet. I'll watch the road.",
            { "Hurry it up. I'm freezing my ass off here.",
                clean = "Hurry it up. I'm freezing out here." },
        },
    },

    -- Gear preparation before an expedition leaves.
    ["voice.prep.fetch"] = {
        common = {
            "Getting the gear. Two minutes.",
            "Fetching what we need from storage.",
            "Hold on. I'm not going out there empty-handed.",
            "Let me grab the tools. Then we go.",
            "Checking the shelves. Somebody always moves things.",
            { "Where the hell did we put it?",
                clean = "Where on earth did we put it?" },
            "One trip to storage, then we leave.",
        },
        practical = { "Gear first. Road second." },
        cautious = { "I want the right tools before we walk out that gate." },
    },
    ["voice.prep.missing"] = {
        common = {
            "Nothing to use in storage. We can't go like this.",
            "Shelf's empty. Somebody find me what I need.",
            "We're missing gear. I'm not leaving without it.",
            { "Not a damn thing on those shelves.",
                clean = "Not a single thing on those shelves." },
            "I've looked twice. It isn't there.",
            "Can't do this with bare hands. Put something in storage.",
        },
    },
    ["voice.prep.daylight"] = {
        common = {
            "Waiting for light. The dark doesn't need our help.",
            "We leave at first light. Not before.",
            "Nobody walks into those woods at night. Sit.",
            "Morning. We go in the morning.",
            "Dark out. We'd only be feeding something.",
        },
    },

    -- Bringing the haul home.
    ["voice.delivery.unload"] = {
        common = {
            "Unloading. Hands, anyone?",
            "Let's get this out of the car before somebody else does.",
            "Trunk's open. Start carrying.",
            "Out it comes. Mind your backs.",
            { "Get it inside. I'm not hauling this twice, damn it.",
                clean = "Get it inside. I'm not hauling this twice." },
            "One armful at a time. It all goes in.",
        },
        practical = { "Unload first. Talk later." },
        caring = { "Don't lift too much at once. We have time." },
    },
    ["voice.delivery.stored"] = {
        common = {
            "Stacked.",
            "That's in. Next one.",
            "Shelved. Somebody write it down.",
            "In the store. Safe as anything is.",
            "Put away. Feels like we actually own something.",
            "There. One less thing lying around.",
            "Stored. Winter can come knocking.",
            { "In. Hell, I might even be useful.",
                clean = "In. Heck, I might even be useful." },
        },
    },
    ["voice.delivery.blocked"] = {
        common = {
            "Nowhere to put it. Storage is full or out of reach.",
            "Can't store this. Somebody make room.",
            "I'll hold onto it. There's no space.",
            { "Full. Where the hell am I supposed to put this?",
                clean = "Full. Where am I supposed to put this?" },
            "No room. I'll try again in a bit.",
            "Shelves are full. I'm not leaving it on the ground.",
        },
    },
    ["voice.delivery.done"] = {
        common = {
            "Everything's put away. That's the trip done.",
            "All of it stored. Now I want coffee.",
            "Done. Every last piece is where it belongs.",
            "That's the haul in. Good work, all of you.",
            "Unloaded. Now we can pretend we live here.",
            { "All stored. Damn good day, considering.",
                clean = "All stored. Good day, considering." },
        },
    },

    -- Searching a site.
    ["voice.search.empty"] = {
        common = {
            "Nothing here. Not even dust worth taking.",
            "Empty. Somebody beat us to it.",
            "Picked clean. Like bones.",
            "Drawers open, shelves bare. Someone left in a hurry.",
            { "Nothing. Not a damn thing.",
                clean = "Nothing. Not a single thing." },
            "This room's been looted twice. I'm the third.",
            "Nothing we need. Moving on.",
            "They took everything but the photographs. Nobody wants those.",
        },
    },
    ["voice.search.blocked"] = {
        common = {
            "Can't get at it. Something's in the way.",
            "Door won't give. I'll try another room.",
            "No way through. Somebody else take that one.",
            { "Blocked. Of course it's damn well blocked.",
                clean = "Blocked. Of course it's blocked." },
            "Can't reach it from here. Moving on.",
        },
    },

    -- Field orders near the player.
    ["voice.field.chop"] = {
        common = {
            "Right. Another tree.",
            "Swinging. Keep clear.",
            "Wood for the fire, sweat for the wood.",
            "Got this one.",
            "Cold enough to see my breath. Keeps me honest.",
            { "Down, you stubborn piece of shit.",
                clean = "Down, you stubborn piece of wood." },
            "I'll take the big one. You take the next.",
            "The axe knows the work better than I do.",
        },
        practical = { "Fall side's clear. Cutting." },
        cautious = { "Watch the road while I swing." },
    },
    ["voice.field.harvest"] = {
        common = {
            "Picking. Quietly.",
            "Ripe enough. Let's take it before the rot does.",
            "Something still grows out here. Hard to believe.",
            "Dirt under the nails. Better than blood.",
            "Somebody planted these. They aren't coming back for them.",
            { "Hell of a garden, for someone who's gone.",
                clean = "Some garden, for someone who's gone." },
            "Fill the bag. Winter is long.",
        },
        caring = { "This will feed somebody. That's enough for me." },
        practical = { "Ripe ones first. Leave the green." },
    },
    ["voice.field.timber"] = {
        common = {
            "Tree's down.",
            "Down. Gather it up.",
            "Timber. Mind the branches.",
            "There it goes. Logs on the ground.",
            "One more down. The woods are getting thinner.",
            { "Down. Hell yes.", clean = "Down. Heck yes." },
        },
    },
    ["voice.field.picked"] = {
        common = {
            "Got it.",
            "In the bag.",
            "That's one more meal.",
            "Picked. Moving down the row.",
            "Good one. Hardly bruised.",
            "Bag's getting heavy. Good.",
        },
    },
    ["voice.field.load"] = {
        common = {
            "In the trunk.",
            "Loading the car. Keep it coming.",
            "Car's filling up.",
            "Stacked in the back. Next.",
            { "Shove it in there. It'll fit, damn it.",
                clean = "Shove it in there. It'll fit." },
        },
    },
    ["voice.field.full"] = {
        common = {
            "Can't carry more.",
            "Hands full. I need the car or a break.",
            "That's my limit. Anything else waits.",
            "No room left on me.",
            { "Full. My back's done with this shit.",
                clean = "Full. My back's done with this." },
        },
    },
    ["voice.field.done"] = {
        common = {
            "That's all of it here. Done.",
            "Nothing left to take. We're finished.",
            "Work's done. Let's not stand around in the open.",
            "Field's cleared. Let's go.",
            "Finished. My hands will remember tomorrow.",
            { "Done. That's a damn day's work.",
                clean = "Done. That's a full day's work." },
        },
    },
}

-- ---------------------------------------------------------------------------
-- Base camp jobs. A start line is said when a resident takes the job, so it
-- reads as intent; a done line follows the verified finish.
-- ---------------------------------------------------------------------------

local jobs = {
    ["voice.job.start.store"] = {
        common = {
            "Putting things where they belong. Somebody has to.",
            "Sorting. It's quiet work. I like quiet work.",
            "Let's make the shelves make sense.",
            "Hauling it in. The pile won't move itself.",
            "Cans with cans, nails with nails. Order keeps us alive.",
            "One shelf at a time. Like counting rosary beads.",
            "Everything in its place. Even if the world isn't.",
            "Who left all this on the floor? Never mind. I've got it.",
        },
        practical = { "Sorting by type. Easier to find in a hurry." },
        caring = { "If it's tidy, we find bandages faster. That matters." },
        low = { "Arranging things for a world that won't arrange itself." },
    },
    ["voice.job.done.store"] = {
        common = {
            "Shelves are in order.",
            "Sorted. You could find anything now. In the dark, even.",
            "Done. Nothing on the floor that shouldn't be.",
            "All put away. For now.",
            "Tidy. For a few hours, anyway.",
            { "Done. Don't mess it up, damn it.",
                clean = "Done. Don't mess it up, please." },
        },
        practical = { "Everything stored where it belongs." },
    },
    ["voice.job.start.unload"] = {
        common = {
            "Unloading the car.",
            "Let's empty this trunk before dark.",
            "Out of the car and into the shed.",
            "Somebody stole this once already. Now it's ours.",
            { "Who packed this trunk? Hell of a puzzle.",
                clean = "Who packed this trunk? Quite a puzzle." },
            "Carrying it in. Hold the door.",
        },
    },
    ["voice.job.done.unload"] = {
        common = {
            "Trunk's empty.",
            "Car's unloaded. Everything's inside.",
            "Done. The car can rest. I can't.",
            "That's the last of it out.",
            "Empty trunk, full shed. Good trade.",
        },
    },
    ["voice.job.start.fuel"] = {
        common = {
            "Filling the car. Nobody light anything.",
            "Gas in the tank. The good stuff's getting rare.",
            "Fueling up. Smells like the old world.",
            "Pouring gas. Don't stand downwind.",
            { "Fuel's worth more than gold now. Don't spill a damn drop.",
                clean = "Fuel's worth more than gold now. Don't spill a drop." },
            "Topping off the tank. In case we need to leave fast.",
        },
        cautious = { "Nobody smoke near me. I mean it." },
    },
    ["voice.job.done.fuel"] = {
        common = {
            "Tank's full.",
            "Car's fed. Ready to run.",
            "Fueled. If we have to run, we can.",
            "Done. The smell's going to stay in my clothes.",
            "Full tank. First good news today.",
        },
    },
    ["voice.job.start.generator"] = {
        common = {
            "Feeding the generator.",
            "Gas for the generator. The lights stay on another day.",
            "Fueling the machine that keeps the dark out.",
            "Topping up the generator. Don't touch anything humming.",
            { "Damn thing drinks more than I used to.",
                clean = "That thing drinks more than I used to." },
            "Generator's thirsty again.",
        },
    },
    ["voice.job.done.generator"] = {
        common = {
            "Generator's full. Lights stay on.",
            "Fueled. Hear it hum? That's civilization.",
            "Done. Another few days of light.",
            "Generator's fed. Listen to it go.",
            "That should keep the fridge cold awhile.",
        },
    },
    ["voice.job.start.tires"] = {
        common = {
            "Pumping tires. Glamorous work.",
            "Flat tires, flat world. I can fix one of those.",
            "Air in the tires. Nobody wants to run on rims.",
            "Tires first. You don't outrun anything on a flat.",
            { "Pump, pump, pump. Hell of a workout.",
                clean = "Pump, pump, pump. Some workout." },
        },
    },
    ["voice.job.done.tires"] = {
        common = {
            "Tires are good.",
            "Pumped. She'll roll.",
            "All four hold air. For now.",
            "Done. My arms hate me.",
            "Tires up. One less way to die on the road.",
        },
    },
    ["voice.job.start.wash"] = {
        common = {
            "Washing the car. Some of this isn't mud.",
            "Cleaning off the blood. Don't ask whose.",
            "Bucket and rag. The world ended and I'm washing a car.",
            { "This shit's baked on. Lovely.",
                clean = "This muck's baked on. Lovely." },
            "If anyone sees us coming, better they see us clean.",
        },
    },
    ["voice.job.done.wash"] = {
        common = {
            "Car's clean. Cleaner than me.",
            "Washed. You can see the paint again.",
            "Done. The water isn't clear anymore.",
            "Clean enough. Nobody will ever know what it hit.",
            "Spotless. Well. Fewer spots.",
        },
    },
    ["voice.job.start.repair"] = {
        common = {
            "Fixing it. Give me room.",
            "Something broke. Something always breaks.",
            "Let's patch this up.",
            "Repairs. The only kind of hope I trust.",
            "Hold still, you old junk. I'm helping.",
        },
    },
    ["voice.job.done.repair"] = {
        common = {
            "Fixed. It'll hold. Probably.",
            "Done. Good as it gets.",
            "Patched up. Don't lean on it.",
            "Works again. Small miracles.",
            "Fixed. For now. Everything is for now.",
        },
    },
    ["voice.job.start.build"] = {
        common = {
            "Building. Hand me nails if you're idle.",
            "Let's put up something that stays up.",
            "Hammer time. Quietly, if possible.",
            "Every board is a wall between us and them.",
            "Measure twice. We don't have lumber to waste.",
            { "Let's build something that doesn't fall down, damn it.",
                clean = "Let's build something that doesn't fall down." },
            "Making the camp a little more ours.",
        },
        brave = { "Give me an hour and I'll give you a wall." },
        cautious = { "Noise carries. I'll be quick." },
    },
    ["voice.job.done.build"] = {
        common = {
            "Built. Stand back and admire it.",
            "Done. It isn't pretty. It's sturdy.",
            "That'll stand. Longer than we will, maybe.",
            "Finished. Another wall between us and the dark.",
            "There. Something new in a world that only takes.",
            { "Built. Damn fine work, if I say so.",
                clean = "Built. Fine work, if I say so." },
        },
    },
    ["voice.job.start.barricade"] = {
        common = {
            "Boarding it up.",
            "Planks on the window. Let them knock.",
            "Nailing it shut. Nobody's getting in this way.",
            "Board by board. Keep the night outside.",
            "Window first. They always come through windows.",
            { "Board the damn thing up and let them scratch.",
                clean = "Board the thing up and let them scratch." },
        },
    },
    ["voice.job.done.barricade"] = {
        common = {
            "Boarded. They'll have to work for it.",
            "Window's shut tight.",
            "Done. One less way in.",
            "That'll hold. Not forever. Long enough.",
            "Sealed. Now we listen to them try.",
        },
    },
    ["voice.job.start.clean"] = {
        common = {
            "Cleaning. The blood doesn't wash itself.",
            "Scrubbing the floor. I won't ask what this was.",
            "Mop and bucket. The glamorous life.",
            "Let's make this place look lived in instead of died in.",
            "Bleach and water. Smells like a hospital. Better than the alternative.",
        },
    },
    ["voice.job.done.clean"] = {
        common = {
            "Clean. Mostly.",
            "Floor's done. Smells like bleach and regret.",
            "Spotless. Close enough for the end of the world.",
            "That stain's gone. The memory isn't.",
            "Done. Somebody else scrub next time.",
        },
    },
    ["voice.job.start.cook"] = {
        common = {
            "Cooking. Stay out of my kitchen.",
            "Supper's started. Don't expect miracles.",
            "Something warm tonight. That's a promise.",
            "Pots on. Somebody watch the window, the smell carries.",
            { "Hell of a menu tonight. Beans, or beans.",
                clean = "Some menu tonight. Beans, or beans." },
            "Grandmother's recipe, minus most of the ingredients.",
        },
        caring = { "Hot food. Everybody eats tonight." },
    },
    ["voice.job.done.cook"] = {
        common = {
            "Food's ready. Eat it while it's hot.",
            "Supper. Don't thank me, just eat.",
            "Done. It isn't good, but it's warm.",
            "Food's up. Come get it before it's cold.",
            "Cooked. The smell alone is worth living for.",
            { "Eat. It isn't poison. Damn near gourmet.",
                clean = "Eat. It isn't poison. Nearly gourmet." },
        },
    },
    ["voice.job.start.gather"] = {
        common = {
            "Gathering for the pile.",
            "Collecting. Every scrap counts.",
            "Picking up what we need. Back soon.",
            "Hauling materials. Arms first, complaints later.",
        },
    },
    ["voice.job.done.gather"] = {
        common = {
            "Pile's growing.",
            "Gathered. That's the lot.",
            "Done. We'll need more, but not today.",
            "Collected. Somebody stack it properly.",
        },
    },
    ["voice.job.blocked"] = {
        common = {
            "Can't finish this. Something's in the way.",
            "Stuck. I'll come back to it.",
            "Not working. Give me a while.",
            "Can't do it yet. I'll try again later.",
            { "Damn it. This isn't happening right now.",
                clean = "Blast it. This isn't happening right now." },
            "I need something I don't have. I'll wait.",
            "Blocked. Story of everything lately.",
            "Not now. Later, maybe.",
        },
        brave = { "It beat me this time. Not next time." },
        practical = { "Can't proceed. I'll retry later." },
        low = { "Of course it doesn't work. Nothing does." },
    },
}
for topic, specification in pairs(jobs) do Lines.POOLS[topic] = specification end

-- ---------------------------------------------------------------------------
-- Crew banter. A beat is one small exchange: an opener, a reply chosen from
-- its alternatives, and sometimes a closing word from the opener. %1 is the
-- other person's name.
-- ---------------------------------------------------------------------------

Lines.BANTER = {
    -- Walking out to a site or back home.
    march = {
        { open = "You hear that?",
            reply = { "Wind. Just wind.", "No. Keep walking." }, close = "Right. Wind." },
        { open = "How far now?",
            reply = { "Far enough to regret it.", "Two miles. Maybe three. Does it matter?" } },
        { open = "I used to drive this road to work.",
            reply = { "Bet it was boring.", "Bet it looked different with people in it." },
            close = "It was boring. I'd give anything for boring." },
        { open = "Ever think about who lived in these houses?",
            reply = { "Every house. Every time.", "No. I can't afford to." } },
        { open = "If I get bit, %1, don't wait. Promise.",
            reply = { "Don't talk like that.", "I promise. Same goes for me." },
            close = "Good. Then we understand each other." },
        { open = "My feet stopped hurting an hour ago.",
            reply = { "That's bad, you know.", "Mine stopped belonging to me yesterday." } },
        { open = { "Damn crows. They follow us everywhere.",
                clean = "Those crows. They follow us everywhere." },
            reply = { "They know where the meals are.",
                "Means nothing's dead ahead. Or everything is." } },
        { open = "What day is it?",
            reply = { "Does it matter?", "Thursday. I think. I stopped counting." },
            close = "Thursday. Fine. Thursday." },
        { open = "Rain's coming.",
            reply = { "Good. It hides our smell.", "Of course it is." } },
        { open = "Remember when the worst thing was a long commute?",
            reply = { "Barely.", "I'd kill for traffic. Real traffic." } },
        { open = "Smell that? Smoke.",
            reply = { "Not ours. Keep moving.", "Somebody else is alive out here." },
            close = "Or was, this morning." },
        { open = "You still carry that photo?",
            reply = { "Every day.", "Lost it at the river. Probably better." } },
        { open = "%1, you're limping.",
            reply = { "I'm fine.", "Old knee. Older than this mess." } },
        { open = { "Every road in this county goes to hell eventually.",
                clean = "Every road in this county goes downhill eventually." },
            reply = { "This one gets there faster.", "Then at least we know the way." } },
        { open = "Why are you smiling?",
            reply = { "I wasn't. Habit from before.", "Thought of something funny. It's gone now." } },
    },
    -- Seated together in the expedition car.
    drive = {
        { open = "Radio still gets that one station.",
            reply = { "The one that loops the weather?", "Turn it off. It's static and ghosts." } },
        { open = "Whose car was this?",
            reply = { "Doesn't matter now.", "Somebody with a lot of parking tickets." },
            close = "Glovebox says Linda. Thanks, Linda." },
        { open = "Don't hit the potholes.",
            reply = { "I'm hitting the ones I can't see.", "They're all potholes now." } },
        { open = "You drive like my father.",
            reply = { "Careful?", "Like someone who's seen what's in the ditch." } },
        { open = "If we break down here, we walk.",
            reply = { "We won't break down.", "Then we walk. Watch the gauge." } },
        { open = "Look. A billboard for life insurance.",
            reply = { "Bit late for that.", "Bet they're not paying out." } },
        { open = "Seat's warm. First warm thing all week.",
            reply = { "Don't get used to it.", "Enjoy it. We walk tomorrow." } },
        { open = { "Who taught you to drive? A damn cow?",
                clean = "Who taught you to drive? A cow?" },
            reply = { "My uncle. Same thing.", "Want to walk?" } },
        { open = "Lights in that house.",
            reply = { "Generator. Or a ghost.", "Keep driving. Not our business." },
            close = "Nothing's our business anymore." },
        { open = "How much gas?",
            reply = { "Enough.", "Enough to get home. Not enough to argue." } },
        { open = "I miss music.",
            reply = { "Hum something.", "I miss silence that wasn't frightening." } },
        { open = "Smell's never coming out of these seats.",
            reply = { "Neither is the blood.", "We're the smell now." } },
    },
    -- Felling and hauling at a wood site.
    wood = {
        { open = "Pass me the whetstone?",
            reply = { "Left it at camp. Swing harder.", "Here. Don't cut your thumb off." } },
        { open = "This used to be somebody's land.",
            reply = { "Now it's everybody's.", "Now it's nobody's. Keep cutting." } },
        { open = "Did you hear the tree fall twice?",
            reply = { "Echo.", "Don't say things like that out here." }, close = "Right. Echo." },
        { open = "Grandfather said wood warms you twice.",
            reply = { "Chopping and burning.", "Carrying it warms you three times." },
            close = "He never carried logs a mile." },
        { open = "How many more?",
            reply = { "Until the trunk's full.", "Until one of us drops. Probably me." } },
        { open = { "Splinter in my palm. Son of a bitch.",
                clean = "Splinter in my palm. Son of a gun." },
            reply = { "Leave it. Pull it at camp.", "Give it here. Hold still." } },
        { open = "Quiet in these woods.",
            reply = { "Too quiet.", "Quiet is good. Quiet means alone." } },
        { open = "%1, mind your swing.",
            reply = { "I mind it fine.", "You mind your feet." } },
        { open = "I could stay out here. Just the trees.",
            reply = { "Until it gets dark.", "Trees don't bite. I see the appeal." } },
        { open = "Sap's freezing on the blade.",
            reply = { "Wipe it, or it'll stick.", "Everything's freezing. Even the sap gave up." } },
        { open = "Smell that? Pine. Like Christmas.",
            reply = { "Christmas. Remember that?", "Don't. Just don't." } },
        { open = "Log's wet.",
            reply = { "They're all wet. Carry it anyway.", "Wet wood, wet boots, wet everything." } },
    },
    -- Searching a building.
    search = {
        { open = "Anything?",
            reply = { "Empty tins and dust.", "Not yet. Keep looking." } },
        { open = "Calendar on the wall. July.",
            reply = { "It's always July in these houses.", "Leave it. Don't read the notes." } },
        { open = "Kids lived here.",
            reply = { "Don't look in that room.", "Lived. Past tense. Keep moving." } },
        { open = "Check the basement?",
            reply = { "You check the basement.", "Nobody checks a basement alone." },
            close = "Then we both don't." },
        { open = "Something died in the bathtub.",
            reply = { "Close the door.", "Not something. Someone." } },
        { open = "Found a letter.",
            reply = { "Don't read it.", "Read it later. Or never." }, close = "Too late. I read it." },
        { open = "This place smells like old coffee.",
            reply = { "Better than the last one.", "Somebody made a pot and never came back." } },
        { open = "Shelves are bare.",
            reply = { "Next room.", "We're not the first. Won't be the last." } },
        { open = "%1, keep your voice down.",
            reply = { "I'm whispering.", "Fine. Fine." } },
        { open = "Photos on the fridge. Happy family.",
            reply = { "Were.", "Don't." }, close = "I know. I know." },
        { open = "Look. A whole drawer of batteries.",
            reply = { "Take them all.", "Finally, something going right." } },
        { open = { "Hell of a house. Shame about the owners.",
                clean = "Some house. Shame about the owners." },
            reply = { "They're in the yard. Some of them.", "Shame about everyone." } },
    },
    -- Waiting on a line at the water.
    fishing = {
        { open = "Anything biting?",
            reply = { "Just the cold.", "Not yet. Fish are smarter than us." } },
        { open = "Water's black today.",
            reply = { "It's always black. That's the mud.", "Don't stare at it. You'll see things." } },
        { open = "My father fished this river.",
            reply = { "Catch anything?", "Mine drank by it." } },
        { open = "Think the fish know?",
            reply = { "Know what?", "They know. They're just keeping quiet." } },
        { open = "Quiet out here.",
            reply = { "That's the point.", "Too quiet. Keep one eye on the bank." } },
        { open = { "Damn line's tangled again.",
                clean = "This line's tangled again." },
            reply = { "Here. Let me.", "Cut it. Tie it again. Patience." } },
        { open = "Cold enough to freeze the bait.",
            reply = { "Then the fish get ice cream.", "Fish don't feel the cold. Lucky fish." } },
        { open = "%1, you're scaring them off.",
            reply = { "I haven't said a word.", "They were never here." } },
        { open = "How long do we wait?",
            reply = { "Until something bites.", "Until dark. Then we eat beans." } },
        { open = "Rain on the water. Pretty, almost.",
            reply = { "Almost.", "Don't get sentimental. It's still rain." } },
    },
    -- A field order near the player.
    field = {
        { open = "Boss wants it all by dusk.",
            reply = { "Boss can swing an axe too.", "Then we'd better work." } },
        { open = "Car's getting full.",
            reply = { "Good. Means we go home.", "Then we stack it on the roof." } },
        { open = "See that house? Door's open.",
            reply = { "Not our job.", "Doors don't open themselves." } },
        { open = "Out in the open like this, my neck itches.",
            reply = { "Mine too. Work faster.", "Keep your back to the car." } },
        { open = { "This is hell on my hands.",
                clean = "This is murder on my hands." },
            reply = { "Gloves next time.", "Hands heal. Mostly." } },
        { open = "Who planted all this?",
            reply = { "Somebody who planned to be here.", "Doesn't matter. We're here now." } },
        { open = "Count them for me?",
            reply = { "Lost count at six.", "Enough. That's the number. Enough." } },
        { open = "Sun's going.",
            reply = { "Then we hurry.", "Sun's always going." } },
        { open = "%1, you missed one.",
            reply = { "I see it.", "Then you get it." } },
        { open = "It's peaceful, almost.",
            reply = { "Almost is the dangerous part.", "Don't jinx it." } },
    },
    -- Two residents at their jobs in camp.
    camp_work = {
        { open = "You eat today?",
            reply = { "Coffee counts.", "Later. After this." }, close = "It doesn't. Eat something." },
        { open = "Pass me that, will you?",
            reply = { "Get it yourself. I'm busy.", "Here. Don't lose it." } },
        { open = "This camp's starting to feel like home.",
            reply = { "Don't say that. Home gets taken.", "Almost. Needs fewer graves." } },
        { open = "%1, you're doing it wrong.",
            reply = { "I'm doing it my way.", "Then show me. Go on." } },
        { open = "Hear the radio last night?",
            reply = { "Just static.", "Somebody reading numbers. Gave me chills." },
            close = "Same. Couldn't sleep after." },
        { open = "How long do you think we'll last here?",
            reply = { "Long enough.", "Until we don't. Keep working." } },
        { open = "My back is killing me.",
            reply = { "Something else will get there first.", "Lift with your legs." } },
        { open = "Smells like rain.",
            reply = { "Good. The barrels need it.", "Then we work wet." } },
        { open = "Remember weekends?",
            reply = { "Barely.", "Every day's Monday now." } },
        { open = { "Who left the damn gate open?",
                clean = "Who left the gate open?" },
            reply = { "Not me.", "Close it. Then we'll find out." } },
        { open = "I dreamt of my sister again.",
            reply = { "Good dream or bad?", "I dream of mine too." },
            close = "Both. That's the trouble." },
        { open = "We should paint something. Make it nicer.",
            reply = { "With what? Blood?", "After the walls are up. Pretty can wait." } },
        { open = "Your hands are shaking.",
            reply = { "Cold.", "They do that now." } },
        { open = "Someday somebody will find this camp and wonder about us.",
            reply = { "Let them wonder.", "Hope we left by choice." } },
    },
}

-- Register every pool with SC.Dialogue. Banter beats register as aggregate
-- open, reply and close pools so the shared line rules see each one; the
-- speaker still says the lines of a single chosen beat.
function Lines.register()
    local dialogue = SC.Dialogue
    if not dialogue or type(dialogue.register) ~= "function" then return false end
    for topic, specification in pairs(Lines.POOLS) do dialogue.register(topic, specification) end
    for context, beats in pairs(Lines.BANTER) do
        local opens, replies, closes = {}, {}, {}
        for _, beat in ipairs(beats) do
            opens[#opens + 1] = beat.open
            for _, reply in ipairs(beat.reply or {}) do replies[#replies + 1] = reply end
            if beat.close ~= nil then closes[#closes + 1] = beat.close end
        end
        dialogue.register("voice.banter." .. context .. ".open", { common = opens })
        dialogue.register("voice.banter." .. context .. ".reply", { common = replies })
        if #closes > 0 then
            dialogue.register("voice.banter." .. context .. ".close", { common = closes })
        end
    end
    return true
end
Lines.register()

return Lines
