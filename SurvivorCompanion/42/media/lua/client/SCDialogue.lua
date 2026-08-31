-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Dialogue = SC.Dialogue or {}
local Dialogue = SC.Dialogue

Dialogue.VERSION = 1

-- Dialogue is grouped by intent rather than by caller. This gives every
-- subsystem the same anti-repetition rules and lets personality influence
-- wording without changing what an action means.
local pools = {
    ["team.recruit"] = {
        common = {
            "All right. I'll come with you.",
            "Okay. We stick together from here.",
            "You've got a deal. I'm with you.",
            "I was hoping you would ask. Let's move.",
            "Fine by me. You won't have to do this alone.",
        },
        brave = { "I'm in. Point me toward the trouble.", "Let's see what we can survive together." },
        cautious = { "I'll join you, but we watch each other's backs.", "All right, as long as we keep an exit open." },
        caring = { "Yes. We will look after each other.", "I'd rather face this with someone. I'm with you." },
        practical = { "Agreed. Two people can cover more ground.", "That makes sense. I'll gather my things." },
    },
    ["team.dismiss"] = {
        common = {
            "I understand. Take care of yourself.",
            "All right. This is where we part ways.",
            "Understood. I hope you make it.",
            "If that is your decision, I'll go.",
            "Then this is goodbye. Stay alive.",
        },
        brave = { "No hard feelings. I'll manage.", "I'll find my own road from here." },
        cautious = { "Fine. I'll leave before it gets dark.", "Understood. I'll find somewhere defensible." },
        caring = { "I wish it had gone differently. Be safe.", "Take care. I mean that." },
        practical = { "Understood. I'll take only what is mine.", "All right. We both know where we stand." },
    },
    ["danger.zombie"] = {
        common = {
            "Zombie! Watch out!", "Dead ahead!", "Contact! Zombie!",
            "Heads up! We've got a zombie!", "Walker! Right there!",
            "Look alive! One of them is close!", "Zombie coming in!",
        },
        brave = { "Zombie! I'll take it!", "Contact! Keep moving!" },
        cautious = { "Zombie! Check your escape route!", "Movement! Zombie nearby!" },
        caring = { "Watch yourself! Zombie!", "Get back! One of them is close!" },
        practical = { "Zombie spotted!", "Contact, close range!" },
        stressed = { "Oh hell, zombie!", "Damn it, one of them is here!" },
    },
    ["danger.one"] = {
        common = {
            "One zombie ahead.", "Single walker, up ahead.", "I've got one moving out there.",
            "One of them, straight ahead.", "Just one zombie in sight.", "One deadhead, out ahead.",
            "Contact. One zombie.", "One walker crossing our path.", "I see one. Keep your eyes on it.",
            "Lone zombie ahead.", "One body moving. Not alive.", "We've got a single contact.",
        },
        brave = { "Only one. I can handle it.", "One walker. Easy does it." },
        cautious = { "One zombie. There may be more behind it.", "Single contact. Check the corners too." },
        caring = { "One zombie ahead. Stay close to me.", "Just one in sight. Watch yourself." },
        practical = { "One confirmed. No others visible.", "Single contact at the moment." },
        stressed = { "One of them. Damn it.", "I see one. Please let it be alone." },
    },
    ["danger.pair"] = {
        common = {
            "Two zombies ahead.", "Pair of walkers, front.", "I've got two moving together.",
            "Two contacts in sight.", "Not one. Two of them.", "Two deadheads crossing ahead.",
            "Watch it. Two zombies.", "There's a pair up ahead.", "Two walkers, close together.",
            "I count two.", "Two bodies moving our way.", "Pair of contacts. Keep some room.",
        },
        brave = { "Two of them. We can split them.", "Pair ahead. I'll take the closer one." },
        cautious = { "Two zombies. Don't let them come side by side.", "I count two. Leave us an exit." },
        caring = { "Two ahead. Stay where I can see you.", "Pair of walkers. Nobody gets isolated." },
        practical = { "Two confirmed, moving together.", "Pair ahead. We can separate them." },
        stressed = { "Two now. Of course there are two.", "Damn it, a pair of them." },
    },
    ["danger.group"] = {
        common = {
            "Three or four zombies ahead.", "Small group. Three, maybe four.",
            "I've got several walkers moving together.", "Group of zombies in front of us.",
            "Multiple contacts. About four.", "Three or four deadheads up ahead.",
            "That's a group, not a pair.", "Several zombies. Keep your spacing.",
            "I count four moving shapes.", "Small pack ahead.",
            "Four walkers, give or take one.", "We've got a cluster of them ahead.",
        },
        brave = { "Small pack. We break them apart first.", "Four ahead. Don't let them surround us." },
        cautious = { "About four. That's enough to trap us.", "Small group. Mark the way back." },
        caring = { "Several ahead. Stay together and don't rush.", "Four walkers. Nobody goes in alone." },
        practical = { "Four contacts. We need space between them.", "Small group confirmed. Choose the ground." },
        stressed = { "There are four of them. This keeps getting worse.", "Damn, that's a whole group." },
    },
    ["danger.crowd"] = {
        common = {
            "Crowd of zombies ahead.", "That's more than a small group.",
            "I've got at least half a dozen.", "Six, maybe eight walkers in sight.",
            "Too many to treat like a quick fight.", "A crowd is gathering up ahead.",
            "Multiple walkers, spread out ahead.", "Big cluster ahead of us.",
            "I count at least six.", "A lot of movement ahead.",
            "Crowd of deadheads. Watch the sides.", "This is becoming a pack.",
        },
        brave = { "Big group. We fight only if we control the ground.", "Crowd ahead. Make every hit count." },
        cautious = { "Six or more. Start looking for another route.", "Crowd ahead. Keep the exit behind us." },
        caring = { "That's a lot of them. Stay close and stay calm.", "Crowd ahead. I don't want anyone separated." },
        practical = { "At least six contacts. Direct engagement is a bad trade.", "Large group. We need distance or a choke point." },
        stressed = { "There are too many. There are way too many.", "Oh hell, look at all of them." },
    },
    ["danger.horde"] = {
        common = {
            "Horde ahead!", "That's a horde. We turn around now.",
            "The whole street is moving.", "More zombies than I can count.",
            "Mass of dead ahead. Do not go that way.", "They're everywhere up there.",
            "Huge horde in front of us.", "That road is lost. Horde.",
            "Wall of walkers ahead.", "I can't count them all.",
            "The dead own that whole block.", "Horde moving this way. We need to disappear.",
        },
        brave = { "Horde! Courage won't fix those numbers.", "That's an army of them. We move." },
        cautious = { "Horde ahead. Quietly back the way we came.", "Too many to count. Break sight and leave." },
        caring = { "Horde! Stay together and follow me out.", "Nobody gets left behind. Move away from them." },
        practical = { "Horde confirmed. This route is closed.", "Mass contact. No engagement. Find another way." },
        stressed = { "Oh God, that's a horde.", "No. No way. There are too many to count." },
    },
    ["signal.one"] = {
        common = {
            "*raises one finger: one walker ahead*", "*closes a fist, then points to one zombie*",
            "*holds up one finger and points ahead*", "*signals one contact, straight ahead*",
            "*taps one finger against their weapon: one*", "*points low, then shows one finger*",
        },
        cautious = { "*signals one walker, then points back to the escape route*" },
        practical = { "*shows one finger: single contact*" },
    },
    ["signal.pair"] = {
        common = {
            "*raises two fingers: two walkers ahead*", "*points ahead, then holds up two fingers*",
            "*signals a pair moving together*", "*shows two fingers and motions for spacing*",
            "*taps twice against their weapon and points forward*", "*signals two contacts near each other*",
        },
        cautious = { "*shows two fingers, then motions to split them apart*" },
        practical = { "*signals two contacts and marks the nearer one*" },
    },
    ["signal.group"] = {
        common = {
            "*holds up four fingers: small group ahead*", "*signals several walkers clustered ahead*",
            "*shows four fingers, then makes a spreading motion*", "*points forward and signals a small pack*",
            "*counts four on one hand and gestures for quiet*", "*signals multiple contacts ahead*",
        },
        cautious = { "*signals four, then traces the route back with one finger*" },
        practical = { "*shows four contacts and points toward better ground*" },
    },
    ["signal.crowd"] = {
        common = {
            "*spreads both hands: large group ahead*", "*signals many walkers and motions everyone down*",
            "*shows both hands, then points away from the crowd*", "*makes a wide circling motion: big pack*",
            "*signals six-plus contacts and a quiet retreat*", "*points ahead, then waves the route closed*",
        },
        cautious = { "*signals a crowd and urgently points toward another route*" },
        practical = { "*marks the route blocked by a large group*" },
    },
    ["signal.horde"] = {
        common = {
            "*spreads both arms wide: horde ahead*", "*signals a mass of walkers, then points back*",
            "*draws a line across their throat and points away from the horde*",
            "*waves both hands low: too many, turn around*", "*points ahead, shakes their head, and signals retreat*",
            "*makes a wide crowd signal, then urgently motions everyone back*",
        },
        cautious = { "*signals a horde and silently orders an immediate withdrawal*" },
        practical = { "*marks the entire route closed: horde*" },
    },
    ["combat.engage"] = {
        common = {
            "Engaging!", "I'm going in!", "Taking it down!", "I've got this one!",
            "Moving in!", "On it!", "Here we go!", "Keep back, I've got it!",
        },
        brave = { "Come on, then!", "My turn!", "Let's finish this!" },
        cautious = { "One target. Keep an exit open!", "Moving in. Watch my flank!" },
        caring = { "Stay behind me!", "I've got it. Keep yourself safe!" },
        practical = { "Target selected. Engaging!", "Closing in now!" },
        stressed = { "Fine! Let's do this!", "Get away from us!" },
    },
    ["combat.engage.one"] = {
        common = {
            "One contact. I'm taking it!", "I've got the lone walker!", "Just one. Moving in!",
            "Single target. Engaging!", "I'll handle this one!", "One walker. Cover me!",
            "Taking the only one in sight!", "I have the single contact!",
        },
        brave = { "Only one? Mine.", "One walker. Let's end it." },
        cautious = { "One target. Watch for the one we can't see.", "I'll take it. Keep checking behind us." },
        caring = { "Stay back. I'll take this one.", "One walker. Keep yourself clear." },
        practical = { "Single target selected.", "Engaging the lone contact." },
        stressed = { "Fine, one of you. Come on!", "One walker. Go down fast." },
    },
    ["combat.engage.pair"] = {
        common = {
            "Two contacts. Take them one at a time!", "Pair ahead. I'm on the closer one!",
            "I'll pull one away from the other!", "Two walkers. Keep them separated!",
            "Engaging the first of two!", "Pair of them. Watch my side!",
            "Two targets. Don't let them line up on us!", "I'm taking the lead walker!",
        },
        brave = { "Two walkers. Pick one and commit!", "Pair ahead. Let's split them." },
        cautious = { "Two contacts. Keep them from flanking us.", "I'll engage. Hold the exit." },
        caring = { "Two of them. Stay close and don't get between them.", "I'll take one. Guard each other." },
        practical = { "Pair confirmed. Isolate the closer target.", "Two targets. Focus one down." },
        stressed = { "Two of them. Fine!", "Damn it, don't let both reach me!" },
    },
    ["combat.engage.group"] = {
        common = {
            "Small group! Hold the line!", "Four contacts. Keep your spacing!",
            "I'm engaging. Don't get surrounded!", "Several walkers. Focus the nearest!",
            "Small pack. Make them come through us one at a time!", "Four or so. Watch the flanks!",
            "Group ahead. Hit one and keep moving!", "Multiple targets. Stay on your feet!",
        },
        brave = { "Small pack. We break them here!", "Four walkers. Keep swinging!" },
        cautious = { "Four contacts. Fight toward the exit.", "Small group. Do not chase into them." },
        caring = { "Stay together! Nobody gets pulled into that group!", "Several ahead. Watch each other!" },
        practical = { "Four contacts. Control the approach.", "Small group. Use the narrow ground." },
        stressed = { "There are four! Keep them off me!", "Too many hands. Don't let them grab you!" },
    },
    ["combat.engage.crowd"] = {
        common = {
            "Big group! Fight only for room!", "Crowd incoming. Keep the exit open!",
            "Six or more! Don't stand still!", "Large pack. Push through, don't chase!",
            "Too many for a clean fight. Make space!", "Crowd ahead. Cover the withdrawal!",
            "Multiple targets. We fight our way out!", "Big cluster. Stay mobile!",
        },
        brave = { "Large group. We hit hard and move!", "Crowd incoming. Hold your nerve!" },
        cautious = { "Six-plus. Every strike should buy an escape step.", "Fight backward. Keep the route clear." },
        caring = { "Stay with me! We're getting everyone out!", "Nobody falls behind. Fight for space!" },
        practical = { "Large group. This is a controlled withdrawal.", "Crowd contact. Conserve room and stamina." },
        stressed = { "There's too many! Keep moving!", "They're closing in. Get them off us!" },
    },
    ["combat.engage.horde"] = {
        common = {
            "Horde! Fight only to escape!", "Mass contact! Clear a path and run!",
            "Don't try to win this! Make a hole!", "Horde on us! Break through!",
            "The street is full! Fight your way out!", "Too many to kill! Buy us room!",
            "Horde! One opening, then we move!", "We're not holding here! Clear the exit!",
        },
        brave = { "Horde! We hit once and get out!", "No heroics! Cut a path!" },
        cautious = { "Horde contact. Do not stop moving!", "Break sight as soon as the path opens!" },
        caring = { "Everyone out! I'll help clear the way!", "Stay together! Nobody disappears in that horde!" },
        practical = { "Horde. Engagement objective is escape only.", "Mass contact. Clear one lane and withdraw." },
        stressed = { "Oh God, they're all coming!", "Horde! Run as soon as you can!" },
    },
    ["combat.retreat"] = {
        common = {
            "Fall back!", "Break contact!", "Pull back, now!", "Back! We need space!",
            "Too many! Move!", "Cover me, I'm moving!", "We're being overrun!",
            "Not here! Move!",
        },
        brave = { "Back up! We fight on better ground!", "Move! I'll cover the retreat!" },
        cautious = { "Exit route! Fall back!", "Bad position! Get out!" },
        caring = { "Everyone back! Stay together!", "Move! I don't want anyone trapped!" },
        practical = { "Position lost! Withdraw!", "Too much pressure! Disengage!" },
        stressed = { "Oh hell, get back!", "They're everywhere! Move!" },
    },
    ["combat.retreat.one"] = {
        common = {
            "Back up! This one's too close!", "Break contact with the lone walker!",
            "One zombie, bad position. Move!", "Give this one space!", "Back away from it!",
            "Not worth a bite. Pull back!", "One contact. Reset the distance!", "Move back and make it follow!",
        },
        cautious = { "One is enough to kill us. Back up.", "Pull it into the open first!" },
        practical = { "Single contact, poor angle. Reposition.", "Reset against the lone target." },
        stressed = { "Get it away from me!", "Back! Back!" },
    },
    ["combat.retreat.pair"] = {
        common = {
            "Two on us! Pull back!", "Break away before they flank us!", "Pair too close. Move!",
            "Back up and separate them!", "Two contacts. Reset the fight!", "Don't get caught between them!",
            "Pull them apart. Fall back!", "Give ground before both can grab!",
        },
        cautious = { "Two angles of attack. Withdraw.", "Back up until they form a line." },
        practical = { "Pair contact. Reposition and isolate one.", "Two targets. Recover spacing." },
        stressed = { "Both of them are on us! Move!", "I can't hold two! Back!" },
    },
    ["combat.retreat.group"] = {
        common = {
            "Small group closing! Fall back!", "Four contacts. Give ground!", "Pull back before they surround us!",
            "Several on us. Move to the choke point!", "Break contact with the group!", "Back! Keep them in front!",
            "We're losing space. Withdraw!", "Four walkers pressing in. Move!",
        },
        cautious = { "Four contacts. The flank is folding. Back out.", "Withdraw while the exit is still open." },
        practical = { "Small group has the advantage. Reposition.", "Four contacts. Trade ground for spacing." },
        stressed = { "They're around us! Get back!", "Too many hands! Move!" },
    },
    ["combat.retreat.crowd"] = {
        common = {
            "Crowd closing in! Run!", "Large group! Break contact now!", "Too many in reach. Move!",
            "We're being compressed! Get out!", "Six-plus on us. Withdraw!", "The exit is closing! Fall back!",
            "Big pack! Stop fighting and move!", "They're flooding the position. Go!",
        },
        cautious = { "Large group. Leave before this becomes a horde.", "Exit now, while we still have one." },
        practical = { "Crowd pressure critical. Disengage.", "Large pack. Position no longer defensible." },
        stressed = { "They're everywhere! Run!", "I can't count them anymore. Go!" },
    },
    ["combat.retreat.horde"] = {
        common = {
            "Horde! Run!", "Break contact! The whole horde is coming!", "Leave everything and move!",
            "We cannot hold this! Get out!", "Horde on top of us! Go, go!", "The street is lost! Run!",
            "Too many! Do not stop!", "Mass of dead incoming! Withdraw now!",
        },
        brave = { "Horde! Nobody plays hero. Move!", "I'll cover the first steps. Run!" },
        cautious = { "Horde! Break sight and keep going!", "Do not look back. Follow the escape route!" },
        caring = { "Everyone with me! Nobody gets left!", "Stay together and run! I'll watch the rear!" },
        practical = { "Horde contact. Full withdrawal.", "Position lost. Immediate evacuation." },
        stressed = { "Oh God, run!", "They're swallowing the whole road! Move!" },
    },
    ["combat.struggle"] = {
        common = {
            "Go down!", "Stay down!", "Why won't you die?", "Damn thing won't drop!",
            "Just die already!", "Come on!", "Almost got it!", "I'm working on it!",
        },
        brave = { "You are not getting through me!", "Come on, fall already!" },
        cautious = { "This is taking too long!", "I need room to finish this!" },
        caring = { "Keep away from them!", "I won't let it reach you!" },
        practical = { "Target is still active!", "It keeps getting back up!" },
        stressed = { "For God's sake, die!", "Why are you still moving?" },
    },
    ["combat.kill"] = {
        common = {
            "It's down!", "Target down!", "One less!", "Got it!",
            "That's one!", "Clear! It's down.", "Not getting back up.", "Dead for good.",
        },
        brave = { "Dropped it!", "Done. Who's next?" },
        cautious = { "It's down. Check around us!", "Target down. Keep watching!" },
        caring = { "It's down. Is everyone all right?", "Clear here. Check yourselves!" },
        practical = { "Confirmed down.", "Target neutralized." },
        stressed = { "Finally! It's down!", "Damn it. Dead at last." },
    },
    ["work.cannot"] = { common = {
        "I can't do that safely.", "That won't work from here.",
        "I can't complete that as things stand.", "I need a better setup before I try that.",
    } },
    ["work.hammer"] = { common = {
        "I need an unbroken hammer.", "Find me a working hammer and I can do it.",
        "I can't start without a usable hammer.", "The hammer is the missing piece here.",
    } },
    ["work.plank"] = { common = {
        "I need a plank.", "We're short one plank for this.",
        "Bring me a plank and I can continue.", "No good. I don't have the lumber I need.",
    } },
    ["work.nails"] = { common = {
        "I need two nails.", "We're out of the nails this needs.",
        "Give me a couple of nails and I'll finish it.", "I can't secure this without nails.",
    } },
    ["work.saw"] = { common = {
        "I need an unbroken saw.", "This needs a working saw.",
        "Find me a usable saw first.", "I can't make the cut with what I have.",
    } },
    ["work.screwdriver"] = { common = {
        "I need an unbroken screwdriver.", "This job needs a working screwdriver.",
        "I can't dismantle it without a screwdriver.", "Find me a usable screwdriver first.",
    } },
    ["work.blowtorch"] = { common = {
        "I need a fueled blowtorch.", "The torch is empty. I can't do this yet.",
        "This needs a working, fueled blowtorch.", "Bring me a torch with fuel and I'll handle it.",
    } },
    ["work.pry"] = { common = {
        "I need a tool that can remove barricades.", "I can't pry this loose with my hands.",
        "Find me a proper prying tool.", "I need leverage before that barricade will move.",
    } },
    ["work.busy"] = { common = {
        "I need to finish what I'm doing first.", "One thing at a time. I'm still busy.",
        "Give me a moment to finish this.", "I heard you. Let me complete this action first.",
    } },
    ["stress.vent"] = {
        common = {
            "Damn it. I need a minute before I say something worse.",
            "This whole damn place is grinding me down.",
            "Hell, I can't keep pretending that run was fine.",
            "For fuck's sake. Just give me some space.",
            "Every little thing is starting to get under my skin.",
            "I swear, one more bad surprise and I'm going to lose it.",
        },
        brave = { "I'm angry, not beaten. Give me a second.", "I hate feeling this powerless." },
        cautious = { "We keep gambling with our lives, and I am sick of it.", "Nobody thinks about the exit until it is too late." },
        caring = { "I am trying not to take this out on anyone.", "I can't keep carrying everyone else's fear too." },
        practical = { "That run was a mess. We need to learn from it.", "We are wasting energy making the same mistakes." },
    },
    ["stress.argument.open"] = { common = {
        "We need to talk about the last run. You took a risk with all of us.",
        "You left the exit exposed back there. I am not letting that slide.",
        "That run nearly got us killed, and everyone is acting like it was nothing.",
        "Someone needs to say it: that plan fell apart the moment we went inside.",
        "I followed your call back there. I need to know you understand what it cost us.",
        "We survived, but that does not make the choices we made good ones.",
    } },
    ["stress.argument.reply"] = { common = {
        "I was there too. You don't get to put all of that on me.",
        "We made the best call we had. Shouting will not change it.",
        "Back off. I am not your punching bag.",
        "You think I don't replay it in my head? I did what I could.",
        "Say what you need to say, but do not pretend you had every answer.",
        "We can fix the plan. We cannot fix this by tearing into each other.",
    } },
    ["stress.withdraw"] = { common = {
        "I need to be alone for a while.", "Do not follow me. I need some quiet.",
        "I can't do another argument right now.", "Give me a little space to clear my head.",
        "I'm stepping away before I say something I regret.", "I need a room, a door, and five minutes of silence.",
    } },
    ["stress.shutdown"] = { common = {
        "I can't do this right now. Please leave me alone.", "I just need to sit here for a while.",
        "Everything feels pointless right now.", "I don't have anything left in me today.",
        "Let me be still for a bit. I can't think.", "I am here, but I am not all right.",
    } },
    ["grief.mourn"] = { common = {
        "%1 is gone. I need a minute.", "I keep expecting to see %1 walk through that door.",
        "We lost %1. I am not ready to pretend I am fine.",
        "I should have said more while %1 was still here.",
        "It is too quiet without %1 here.", "I keep thinking there was something else I could have done for %1.",
        "I know %1 is gone. My mind hasn't caught up yet.", "Give me a moment. I was just thinking about %1.",
    }, caring = { "I hope %1 knew how much they mattered to us.", "%1 deserved more time than this." },
      practical = { "We still have work to do. I just need a moment for %1 first." },
      brave = { "I'll keep moving. Just not this second. Not after losing %1." },
      cautious = { "I keep wondering which choice might have brought %1 home." } },
    ["stress.minor.venter"] = { common = {
        "This pressure is getting to me.", "I need to let some of this out.",
        "I'm wound too tight. Give me a second.", "I can feel my temper getting shorter.",
    } },
    ["stress.minor.restless"] = { common = {
        "I need something useful to do before I start climbing the walls.",
        "Standing around is making this worse.", "Give me a job. Any useful job.",
        "I need to move before I wear a hole in the floor.",
    } },
    ["stress.minor.confronter"] = { common = {
        "We need to stop making the same mistakes.", "Something about our plan has to change.",
        "We keep avoiding the hard conversation.", "I am not staying quiet if this keeps happening.",
    } },
    ["stress.minor.withdrawer"] = { common = {
        "I could use a little space.", "I need a few quiet minutes.",
        "Let me get my thoughts back in order.", "I am going to keep to myself for a bit.",
    } },
    ["stress.minor.shutdown"] = { common = {
        "I am not doing well. I am trying to hold it together.", "Everything feels heavier today.",
        "I am running out of ways to say I am tired.", "I can function. I just can't pretend I am fine.",
    } },
    ["joy.focused"] = { common = {
        "I know what needs doing. Let me get through the list.", "My head is clear today. Put me to work.",
        "For once, everything feels manageable.", "I have a rhythm going. Let me keep it.",
    } },
    ["joy.rallying"] = { common = {
        "Look at us. We are still here, and we are getting better at this.",
        "We made it this far together. That has to count for something.",
        "This group is tougher than any of us expected.", "We have had worse days. We are still standing.",
    } },
    ["joy.caretaker"] = { common = {
        "Everyone take a breath. I will check bandages and make sure we are all right.",
        "Let me look after the small things before they become big things.",
        "We are safe for a moment. Let me check on everyone.", "Nobody ignores a wound today. I mean it.",
    } },
    ["joy.organizer"] = { common = {
        "This place is finally starting to work like a real camp.",
        "The supplies are sorted, the doors hold, and I can finally breathe.",
        "We are turning this place into something worth defending.", "A little order makes the world feel less broken.",
    } },
    ["joy.bold"] = { common = {
        "We have momentum. Let us use it without getting careless.", "I feel ready. Let's make today count.",
        "For once, I like our chances.", "We can handle the next run. Smart and steady.",
    } },
    ["supply.answer.soon"] = { common = {
        "All right. I will hold you to that.", "Okay. Soon, then. I can work with that.",
        "Good. Just don't let it slip through the cracks.", "That is enough for now. Tell me when we leave.",
    } },
    ["supply.answer.join"] = { common = {
        "Good. I will get my gear ready.", "All right, I am coming with you.",
        "Works for me. Give me a moment to pack.", "Then we do it together. I'll be ready.",
    } },
    ["supply.answer.later"] = { common = {
        "Fine. But we can't keep putting it off.", "Not now, then. Just remember that we still need it.",
        "I can wait, but the shelves will not fill themselves.", "All right. I will ask again if our supplies get worse.",
    } },
    ["supply.answer.cannot"] = { common = {
        "I understand. We make do with what we have.", "I don't like it, but I understand the reason.",
        "Then we stretch the supplies and keep our eyes open.", "All right. We adapt until the situation changes.",
    } },
    ["supply.question"] = {
        common = {
            "When are we making the next supply run?", "Do we have another supply run planned?",
            "The shelves are getting thin. When do we head out again?",
            "We should talk about our next run. When are we going?",
            "How long before we make another supply trip?", "Are we going out for supplies soon?",
        },
        cautious = { "Before stocks get critical, when is our next supply run?" },
        practical = { "I checked our stores. We need to schedule another supply run." },
        caring = { "Can we plan a supply run before anyone goes without?" },
        brave = { "Say the word and I am ready for another supply run." },
    },
    ["status.grief"] = { common = {
        "I am not all right yet. %1 is gone, and I need time.",
        "I am managing, but I keep thinking about %1.", "Some moments are easier than others. I still miss %1.",
        "I can do my job. I just haven't made peace with losing %1.",
        "Honestly? I am still grieving %1.", "I keep expecting %1 to answer when someone calls out.",
    } },
    ["status.knox"] = { common = {
        "I need you to know something is wrong. It feels like Knox symptoms.",
        "Something is wrong with me. It could be the Knox infection.",
        "I am showing symptoms, and I don't think this is ordinary sickness.",
        "We need to talk somewhere private. I may be infected.",
    } },
    ["status.medical"] = { common = {
        "I need treatment and a clean bandage.", "I am hurt. I need someone to look at this.",
        "My wounds need attention before they get worse.", "I could use medical help and fresh bandages.",
        "I am still functional, but I need treatment.",
    }, brave = { "I can keep moving, but patch me up when we get a chance." },
      cautious = { "This wound is a liability. We should treat it now." } },
    ["status.water"] = { common = {
        "Water, if we can spare it. I am getting very thirsty.", "I need a drink soon.",
        "My canteen is empty and I am running dry.", "Water is my first priority right now.",
        "I can keep going, but not long without water.",
    } },
    ["status.food"] = { common = {
        "Food would help. I am running on empty.", "I need something to eat soon.",
        "I have not eaten enough. It is starting to slow me down.", "My first need is food.",
        "I am hungry enough that it is getting hard to focus.",
    } },
    ["status.safety"] = { common = {
        "I need a quiet minute somewhere safe.", "I am too wound up. I need somewhere secure to breathe.",
        "Get me behind a locked door for a minute and I will be fine.",
        "I need the pressure to stop for a moment.", "Somewhere safe and quiet. That is what I need.",
    } },
    ["status.bandages"] = { common = {
        "We should find clean bandages before someone needs one.", "Our medical supplies are too low.",
        "We need more clean bandages in reserve.", "First-aid stock is thin. We should fix that.",
        "Nobody is bleeding yet, but we are out of clean bandages.",
    } },
    ["status.ammunition"] = { common = {
        "I am short on ammunition. I will save what I have.", "My ammunition is nearly gone.",
        "I need more rounds before the next serious fight.", "I am conserving ammunition until we restock.",
        "This firearm will not help much without more ammunition.",
    } },
    ["status.ready"] = {
        common = {
            "I am all right for now. Ready when you are.", "Doing fine. Tell me what comes next.",
            "No urgent problems. I am ready to move.", "I have what I need for now.",
        },
        brave = { "I am holding up. Point me where you need me.", "Ready. Let's not waste the daylight." },
        cautious = { "I am holding up. I am still watching our exits.", "Fine for now. I would like to keep it that way." },
        caring = { "I am all right. How are you holding up?", "I am okay. Let me know if anyone else needs help." },
        practical = { "I am holding up. Our supplies and gear are in order for now.", "Everything important is accounted for. I am ready." },
        hopeful = { "Better than yesterday. I will take that.", "Honestly? I feel pretty good today." },
    },
    ["status.shaken"] = { common = {
        "Physically I am okay. I am still trying to settle my nerves.",
        "Nothing is broken. My hands just need to stop shaking.",
        "I am alive. Give me a little time to come down from that.",
        "I can keep going, but I am not calm yet.", "Ask me again when my heart stops trying to climb out of my chest.",
    } },
    ["opinion.danger"] = { common = {
        "We are pushing our luck. I want a clear way out before we go farther.",
        "This is getting dangerous. We need an exit plan now.", "Too much pressure and not enough room. We should pull back.",
        "I don't like this position. We are one surprise away from being trapped.",
    } },
    ["opinion.guard"] = { common = {
        "This position can work, but I am keeping an eye on the exits.",
        "I can hold here. The approach gives me enough warning.", "The spot is defensible, as long as nobody blocks the retreat.",
        "I will guard it, but I want the doors and windows checked.",
    } },
    ["opinion.scavenge"] = { common = {
        "I can search as we move. I will leave anything you have already claimed alone.",
        "I will keep an eye out for useful supplies without slowing us down.",
        "I can scavenge this route. I will avoid containers you already searched.",
        "I will take essentials and leave the junk behind.",
    } },
    ["opinion.general"] = {
        common = { "We choose useful risks and keep a way home.", "I think the plan works if we stay disciplined." },
        brave = { "We can handle a fight, but only if it gets us somewhere.", "I am willing to take the risk if the goal matters." },
        cautious = { "Slow and deliberate. I want a clear way back out.", "I would rather arrive late than walk blind into a room." },
        caring = { "We stay together and avoid fights that put either of us at needless risk.", "Nobody gets left behind for a bag of supplies." },
        practical = { "We conserve ammunition, keep our tools ready, and choose useful fights.", "The plan is sound if the cost stays lower than the reward." },
    },
    ["relationship.family"] = { common = {
        "You are family to me now. I am not walking away.", "Whatever happens next, you are not facing it alone.",
        "I stopped thinking of this as an arrangement a long time ago. You are family.",
        "I trust you like family. That is the truth of it.",
    } },
    ["relationship.close"] = { common = {
        "I trust you with my life. That is not something I say lightly.", "You have proven yourself to me more than once.",
        "If things go bad, I know you will still be there.", "We have become close. Closer than I expected anyone to get.",
    } },
    ["relationship.trusted"] = { common = {
        "We have been through enough that I know you will be there.", "You have earned my trust.",
        "I don't agree with every call, but I trust you to make one.", "I know where I stand with you, and that matters.",
    } },
    ["relationship.ally"] = { common = {
        "We work well together. Trust takes time, but we are getting there.", "You have been fair with me so far.",
        "I think this partnership has a chance.", "We are still learning each other, but I trust you more than I did.",
    } },
    ["relationship.cautious"] = { common = {
        "I am still getting to know you. Give me time.", "I don't know you well enough to answer that yet.",
        "Trust comes slowly for me now.", "We are not enemies. The rest still has to be earned.",
    } },
    ["encourage.recent"] = { common = {
        "I heard you. Give me a minute to breathe.", "I appreciate it. Let the words settle for a moment.",
        "You already helped. I just need a little time now.", "I am listening. I can't turn it around all at once.",
    } },
    ["encourage.not_needed"] = { common = {
        "I am good. Save that speech for when one of us really needs it.", "I am all right, but thank you for checking.",
        "Keep that encouragement ready. Today I am doing fine.", "No need to worry about me right now.",
    } },
    ["encourage.accept"] = { common = {
        "Thank you. I needed to hear that.", "That helped more than I expected.",
        "All right. I will keep trying.", "Thanks. I was getting lost in my own head.",
        "I am not fixed, but I feel steadier. Thank you.",
    } },
    ["praise.none"] = { common = {
        "Thanks, but let us save the celebration until the work is done.", "I appreciate it, but I have not earned a victory speech yet.",
        "Hold that thought until we have something real to celebrate.", "Thanks. For now, let's stay focused.",
    } },
    ["praise.accept"] = { common = {
        "That means more than you know.", "Thank you. I am proud that I could help.",
        "I was just doing my part, but I appreciate you saying it.", "Thanks. It is good to know the effort mattered.",
        "I will remember that. Thank you.",
    } },
    ["memory.companion_died"] = { common = {
        "%1 died. I keep thinking about the time we had together.",
        "I still catch myself remembering %1 at the strangest moments.",
        "Losing %1 changed this place. It has not felt the same since.",
        "I remember %1. I don't want any of us to forget.",
        "There are things I wish I had said to %1 while there was time.",
    } },
    ["plans.none"] = { common = {
        "Nothing specific. I need a little time to think.", "No real plan yet. I am still working that out.",
        "Ask me again later. Nothing has settled into a goal yet.", "Right now I am focused on getting through the day.",
    } },
    ["plans.reserved"] = { common = {
        "I am not ready to talk about that yet.", "That is personal. Give me a little more time.",
        "I have something in mind, but I don't know you well enough yet.", "Not yet. I need to keep that to myself for now.",
    } },
    ["plans.keep_medical_ready"] = { common = {
        "I would feel better if we kept two clean bandages ready.", "I want a proper reserve of clean bandages.",
        "My priority is making sure a small wound never becomes a death sentence.", "Let's keep medical supplies ready before the next emergency.",
    } },
    ["plans.find_something_to_read"] = { common = {
        "I would like to find something worth reading when things are quiet.", "I miss having a good book for the quiet hours.",
        "If we see anything worth reading, I would like to bring it home.", "My plan is simple: find a book and let my mind go somewhere else for a while.",
    } },
    ["plans.put_gear_in_order"] = { common = {
        "I want to repair our worn gear before it fails us.", "We should put the equipment in order while it is still fixable.",
        "My next job is checking every tool and repairing what I can.", "I want our gear ready before we depend on it again.",
    } },
    ["plans.improve_shelter"] = { common = {
        "I want to make this place a little harder for the dead to enter.", "This shelter needs another layer of defense.",
        "I keep seeing weak points in the base. I want to fix them.", "My goal is to make this place safer before the next horde finds it.",
    } },
    ["plans.share_a_proper_meal"] = { common = {
        "I miss sitting down for a proper meal with someone.", "I want us to share one meal without rushing or standing watch over the plate.",
        "A real meal together would remind me what we are surviving for.", "My plan? Find enough food that we can sit down and eat like people again.",
    } },
    ["plans.recover_keepsake"] = { common = {
        "I am missing something personal. I would like it back.", "There is a keepsake I left behind. I still think about recovering it.",
        "I lost something that mattered to me. I want to go back for it someday.", "My goal is to recover one piece of my old life.",
    } },
    ["crisis.confess"] = { common = {
        "I was bitten. We need to decide what happens next.", "There is something you need to see. It's a bite.",
        "I can't hide this any longer. One of them bit me.", "I was bitten out there. I am sorry.",
        "Listen to me. I have a bite, and we need a plan.",
    } },
    ["crisis.protective"] = { common = {
        "We do not abandon our own. We watch them and keep them safe.",
        "They are still one of us. Nobody makes a decision alone.",
        "We keep them close, keep watch, and treat them like a person.",
    } },
    ["crisis.compassionate"] = { common = {
        "Give them a quiet room and a little dignity.", "Whatever happens, they should not face it alone.",
        "Keep them comfortable. We can be careful without being cruel.",
    } },
    ["crisis.pragmatic"] = { common = {
        "Separate them, keep watch, and make an exit plan.", "We need a secure room and someone on watch.",
        "No panic. Quarantine first, then we decide with clear heads.",
    } },
    ["crisis.fearful"] = { common = {
        "They cannot stay among us. It is too dangerous.", "Get them away from the sleeping area now.",
        "One mistake and we all wake up dead. Move them out.",
    } },
    ["crisis.authoritarian"] = { common = {
        "We decide this now, before they turn.", "Secure them. Nobody opens that door without permission.",
        "The risk is settled. Quarantine them immediately.",
    } },
    ["faction.warn.outer"] = { common = {
        "Stay away. This house is occupied.", "Stop there. We don't trust strangers.",
        "That is close enough. Turn around.", "Hold it. This place is claimed.",
        "Keep your distance and nobody gets hurt.", "We see you. Do not approach the house.",
    } },
    ["faction.warn.inner"] = { common = {
        "Do not come any closer.", "Stop right there.", "One more step and we have a problem.",
        "Back up. Now.", "You are close enough. Stay where you are.",
    } },
    ["faction.warn.weapon"] = { common = {
        "Lower your weapon!", "Put the weapon down!", "Muzzle down, stranger!",
        "Don't point that at us!", "Lower it now if you want to keep talking!",
    } },
    ["faction.warn.leave"] = { common = {
        "Leave our house. Last warning.", "Out. You have been warned.",
        "Get off our property before this turns ugly.", "This is your last chance to walk away.",
    } },
    ["faction.restitution"] = { common = {
        "Leave the restitution where we can see it.", "Set the payment down and step away.",
        "Put what you owe us on the ground. We will collect it.",
        "Leave the restitution outside and keep your hands visible.",
    } },
    ["faction.hostile"] = { common = {
        "You were warned!", "Get away from our home!", "Back off, now!",
        "That is it! Get out!", "You chose this, stranger!",
    } },
    ["faction.recruit.candidate"] = { common = {
        "I can try one run with you. Then I decide.", "One trip. I want to see how you handle yourself.",
        "I will come for a trial run, nothing more yet.", "Let me test the road with you before I promise anything.",
    } },
    ["faction.recruit.trial"] = { common = {
        "One run. I am still responsible for getting myself home.",
        "I am coming, but my place here is not settled yet.", "This is a trial. We both get to judge how it goes.",
        "All right. I have my gear. Let's see if this works.",
    } },
    ["faction.recruit.return"] = { common = {
        "I am going home. This is where I belong.", "I gave it a fair try. My people need me here.",
        "This life is not for me. I am returning to the house.", "No anger. I just know where I need to be.",
    } },
    ["faction.recruit.join"] = { common = {
        "I have made my choice. I am staying with you.", "The trial is over. I want to remain with your group.",
        "I trust you. From now on, I am one of yours.", "I talked it through with myself. I am staying.",
    } },
    ["faction.recruit.more_time"] = { common = {
        "I need more time before I make that choice.", "I am not ready to decide yet. Give me another run.",
        "Ask me again later. I need to see more.", "I am still weighing it. Do not push me yet.",
    } },
    ["faction.life.greeting.Wary"] = { common = {
        "State your business from there.", "Keep your hands where I can see them.",
        "We can hear you from where you are. Speak.", "Stop at the boundary and tell us what you want.",
    } },
    ["faction.life.greeting.Tolerated"] = { common = {
        "We can talk here. Do not enter the house.", "All right. What do you need?",
        "You can approach the gate, no farther.", "We remember you. Say what you came to say.",
    } },
    ["faction.life.greeting.Trusted"] = { common = {
        "Good to see a familiar face.", "Come closer. We may have news for you.",
        "You are welcome at the gate.", "Good, you made it back. What can we do for you?",
    } },
    ["faction.life.supply_crisis"] = { common = {
        "We are running out of %1.", "Our %1 stock is almost gone.",
        "We have a serious shortage of %1.", "If we cannot find %1 soon, this house is in trouble.",
    } },
    ["faction.life.illness"] = { common = {
        "Someone inside is sick. Keep your distance.", "We have illness in the house. Do not come closer.",
        "One of ours is unwell. We are limiting contact.", "Stay at the gate. We cannot risk spreading this.",
    } },
    ["faction.life.dispute"] = { common = {
        "You said the last run was safe!", "Stop blaming me for every bad call.",
        "We cannot keep wasting supplies like this.", "Lower your voice. We have enough trouble outside.",
        "You never listen until something goes wrong!", "We agreed on the plan, and then you changed it!",
        "This is not helping. We need an answer, not another argument.",
    } },
    ["faction.life.plan"] = { common = {
        "We should review tomorrow's plan.", "Let's settle the next watch and supply jobs.",
        "Before we sleep, we need to agree on tomorrow.", "Come here. I want to go over the plan again.",
    } },
    ["faction.life.need_rest"] = { common = {
        "I need to sit down for a while.", "I am not feeling well. I need to rest.",
        "Give me a quiet place to sit.", "I need a break before I can do anything else.",
    } },
    ["faction.life.check_supplies"] = { common = {
        "Check every bag. We are short on supplies.", "Go through the stores again. We are missing something.",
        "Count everything. We need to know exactly what is left.", "Search the containers. Our stock is too low.",
    } },
    ["faction.tone.Paranoid"] = { common = {
        "Careful answer:", "Listen closely:", "This is all we are saying:", "Keep this between us:"
    } },
    ["faction.tone.Generous"] = { common = {
        "Straight answer:", "Honestly:", "We can tell you this:", "Here is the truth:"
    } },
    ["faction.tone.Militarized"] = { common = {
        "Situation report:", "Current assessment:", "Here is the position:", "Our status is this:"
    } },
    ["faction.tone.Desperate"] = { common = {
        "We will be honest:", "There is no point hiding it:", "Truth is:", "What you need to understand is:"
    } },
    ["faction.tone.Isolationist"] = { common = {
        "This stays at the gate:", "We will tell you this much:", "From there, listen:", "This does not buy you entry:"
    } },
    ["faction.tone.Resourceful"] = { common = {
        "Here is what matters:", "The useful answer is:", "What we know is:", "The practical situation is:"
    } },
    ["faction.status.mourning"] = { common = {
        "We lost %1. We are keeping watch, but give us time to grieve.",
        "%1 died. The house is still secure, but nobody here is pretending it does not hurt.",
        "We are mourning %1. Business can wait unless it is urgent.",
        "The watch continues, even after losing %1. Keep this conversation brief.",
    } },
    ["faction.status.normal"] = { common = {
        "We are %1 toward you. Supplies are %2.",
        "Our position toward you is %1, and our stores are %2.",
        "Right now relations are %1. Supply levels remain %2.",
        "The house stands. We are %1 toward you, with %2 supplies.",
    } },
    ["faction.access"] = { common = {
        "Ask clearly and keep your weapon lowered. The household will decide.",
        "Keep your hands visible, state your reason, and we will consider access.",
        "Lower the weapon and make your request. Entry is the household's decision.",
        "You can ask. Whether the door opens depends on how you behave.",
    } },
}

local actorHistory = setmetatable({}, { __mode = "k" })
local idHistory = {}

local function U() return SC.GameplayUtil end

local function actorId(actor)
    local utility = U()
    if utility and type(utility.idOf) == "function" then
        local ok, value = pcall(utility.idOf, actor)
        if ok and value then return tostring(value) end
    end
    return tostring(actor or "survivor")
end

local function runtimeFor(actor)
    if actor ~= nil then
        local runtime = actorHistory[actor]
        if not runtime then
            runtime = { sequence = 0, recent = {}, last = nil }
            actorHistory[actor] = runtime
        end
        return runtime
    end
    local id = "survivor"
    idHistory[id] = idHistory[id] or { sequence = 0, recent = {}, last = nil }
    return idHistory[id]
end

local function commandState(actor, supplied)
    if type(supplied) == "table" then return supplied end
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return {}
end

local function styleFor(state, options)
    options = type(options) == "table" and options or {}
    local profile = type(state.personalityProfile) == "table" and state.personalityProfile or {}
    local voice = tostring(options.voice or profile.archetype or state.personality or "practical")
    if voice ~= "brave" and voice ~= "cautious" and voice ~= "caring" and voice ~= "practical" then
        voice = "practical"
    end
    local mood = options.mood
    if mood == nil then
        local stress = tonumber(state.stress) or 0
        local morale = tonumber(state.morale) or 55
        if stress >= 65 then mood = "stressed"
        elseif morale <= 28 then mood = "low"
        elseif morale >= 72 then mood = "hopeful"
        else mood = "steady" end
    end
    return voice, tostring(mood)
end

local function appendUnique(target, source, seen)
    if type(source) == "string" then source = { source } end
    if type(source) ~= "table" then return end
    for _, value in ipairs(source) do
        if type(value) == "string" and value ~= "" and not seen[value] then
            target[#target + 1] = value
            seen[value] = true
        end
    end
end

local function candidatesFor(specification, voice, mood)
    if type(specification) == "string" then return { specification } end
    if type(specification) ~= "table" then return {} end
    if #specification > 0 then
        local result, seen = {}, {}
        appendUnique(result, specification, seen)
        return result
    end
    local result, seen = {}, {}
    appendUnique(result, specification.common or specification.all, seen)
    appendUnique(result, specification[voice], seen)
    appendUnique(result, specification[mood], seen)
    return result
end

local function interpolate(value, arguments)
    local result = tostring(value or "")
    for index, argument in ipairs(type(arguments) == "table" and arguments or {}) do
        result = string.gsub(result, "%%" .. tostring(index), function() return tostring(argument) end)
    end
    return result
end

local function recentlyUsed(value, recent)
    for _, prior in ipairs(recent or {}) do if prior == value then return true end end
    return false
end

function Dialogue.register(topic, specification)
    if type(topic) ~= "string" or topic == "" or type(specification) ~= "table" then
        return false, "invalid_dialogue_pool"
    end
    pools[topic] = specification
    return true, "dialogue_pool_registered"
end

function Dialogue.has(topic)
    return type(topic) == "string" and type(pools[topic]) == "table"
end

function Dialogue.threatBand(count)
    local amount = math.max(0, math.floor(tonumber(count) or 0))
    if amount <= 1 then return "one", 1 end
    if amount == 2 then return "pair", 2 end
    if amount <= 4 then return "group", 3 end
    if amount <= 8 then return "crowd", 4 end
    return "horde", 5
end

function Dialogue.threatTopic(prefix, count)
    local band, rank = Dialogue.threatBand(count)
    local topic = tostring(prefix or "danger") .. "." .. band
    if Dialogue.has(topic) then return topic, band, rank end
    return tostring(prefix or "danger"), band, rank
end

function Dialogue.choose(actor, topic, specification, arguments, options)
    if type(topic) ~= "string" or topic == "" then return nil, "invalid_dialogue_topic" end
    options = type(options) == "table" and options or {}
    local runtime = runtimeFor(actor)
    local state = commandState(actor, options.state)
    local voice, mood = styleFor(state, options)
    local source = specification or pools[topic]
    local candidates = candidatesFor(source, voice, mood)
    if #candidates == 0 then
        if type(options.fallback) ~= "string" or options.fallback == "" then
            return nil, "dialogue_pool_empty"
        end
        candidates[1] = options.fallback
    end
    local recent = runtime.recent[topic] or {}
    local available = {}
    for _, line in ipairs(candidates) do
        if not recentlyUsed(line, recent) and line ~= runtime.last then available[#available + 1] = line end
    end
    if #available == 0 then
        for _, line in ipairs(candidates) do
            if line ~= runtime.last or #candidates == 1 then available[#available + 1] = line end
        end
    end
    if #available == 0 then available = candidates end
    runtime.sequence = runtime.sequence + 1
    local current = U() and type(U().nowMs) == "function" and U().nowMs() or 0
    local salt = actorId(actor) .. ":" .. topic .. ":" .. tostring(runtime.sequence)
        .. ":" .. tostring(options.salt or "") .. ":" .. tostring(math.floor(current / 250))
    local hash = U() and type(U().stableHash) == "function" and U().stableHash(salt) or #salt * 7919
    local selected = available[(math.abs(hash) % #available) + 1]
    recent[#recent + 1] = selected
    local maximum = math.max(1, math.min(tonumber(options.recentLimit) or 3, #candidates - 1))
    while #recent > maximum do table.remove(recent, 1) end
    runtime.recent[topic], runtime.last = recent, selected
    return interpolate(selected, arguments), {
        topic = topic, voice = voice, mood = mood, poolSize = #candidates,
        sequence = runtime.sequence,
    }
end

function Dialogue.say(actor, topic, specification, arguments, options)
    local line, detail = Dialogue.choose(actor, topic, specification, arguments, options)
    if not line then return false, detail end
    if not U() or type(U().say) ~= "function" then return false, "speech_unavailable" end
    local spoken = U().say(actor, line)
    if spoken == true then
        local runtime = runtimeFor(actor)
        runtime.lastSpokenAt = U() and type(U().nowMs) == "function" and U().nowMs() or 0
        runtime.lastSpokenTopic = topic
    end
    return spoken == true, spoken == true and line or "speech_rejected", detail
end

function Dialogue.lastSpokenAt(actor)
    return tonumber(runtimeFor(actor).lastSpokenAt) or -math.huge
end

function Dialogue.lastSpokenTopic(actor)
    return runtimeFor(actor).lastSpokenTopic
end

function Dialogue.reset(actor)
    if actor ~= nil then
        actorHistory[actor] = nil
    else
        actorHistory = setmetatable({}, { __mode = "k" })
        idHistory = {}
    end
    return true
end

function Dialogue.poolSize(topic, actor, state)
    local voice, mood = styleFor(commandState(actor, state), {})
    return #candidatesFor(pools[topic], voice, mood)
end

function Dialogue.topics()
    local result = {}
    for topic in pairs(pools) do result[#result + 1] = topic end
    table.sort(result)
    return result
end

SC.Modules = SC.Modules or {}
SC.Modules.dialogue = true
return Dialogue
