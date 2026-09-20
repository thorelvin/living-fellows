-- SPDX-License-Identifier: MIT

-- Party banter and small social encounters. Most lines are speech-only; camp
-- conversations and first meetings briefly use SC.Positioning so both people
-- face one another without taking over ordinary movement for long. Cooldowns
-- keep the moments from piling up:
--   * a rare cause-specific explanation when combat decides to withdraw,
--   * a deadpan distraction shout when a companion is surrounded or held by a
--     grab (or a taunt when an ally is grabbed nearby),
--   * a joke when the player has stood still for a few minutes,
--   * a remark the first time the party walks into a notable room type,
--   * a one-time hello when a companion meets a calm new survivor,
--   * a short two-person conversation while residents are idle at camp.
-- Every line goes through SC.Dialogue in the speaker's own voice.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Dialogue and type(require) == "function" then pcall(require, "SCDialogue") end

SC.Banter = SC.Banter or {}
local Banter = SC.Banter

local function U() return SC.GameplayUtil end

local function config(key, fallback)
    local value = tonumber(U().config(key))
    if value == nil then return fallback end
    return value
end

-- ---------------------------------------------------------------------------
-- Lines
-- ---------------------------------------------------------------------------

local POOLS = {
    ["banter.interior.dread"] = {
        common = {
            "Did you hear that? Something in here does not feel right.",
            "That sound is getting under my skin.",
            "I know you are calm, but this place is making me nervous.",
            "There is something in these walls. I can feel it.",
        },
        brave = { "I heard it. I am fine. Mostly." },
        cautious = { "That noise came from inside. We should check our way out." },
        caring = { "Tell me you heard that too." },
        practical = { "Unidentified sound, close by. Stay alert." },
        stressed = { "There! Again. You heard that, right?" },
    },
    ["banter.interior.panic_onset"] = {
        common = {
            "I need a second. I cannot get my breathing right.",
            "This is too close. I am starting to lose it.",
            "My hands are shaking. Give me a moment.",
            "I am panicking. I know it. Just stay near me.",
        },
        brave = { "I can do this. I just need one breath." },
        cautious = { "We need space. Now. I cannot think in this crowd." },
        caring = { "Stay where I can see you, please." },
        practical = { "Panic is setting in. I need a clean exit." },
        stressed = { "I cannot breathe. I cannot breathe." },
    },
    ["banter.interior.panic_recovery"] = {
        common = {
            "All right. I have my breathing back.",
            "I am steady again. Sorry about that.",
            "The shaking stopped. I can think now.",
            "I am okay. Not good, but okay.",
        },
        brave = { "Back in control. Let us keep moving." },
        cautious = { "Better. I still want an exit close." },
        caring = { "Thank you for staying close. I am all right now." },
        practical = { "Breathing normal. I am functional again." },
    },
    ["banter.interior.nicotine"] = {
        common = {
            "I could really use a cigarette right now.",
            "If you see a pack, remember me. This is getting rough.",
            "I hate to ask, but have you seen any cigarettes?",
            "The nicotine is wearing off. I am getting twitchy.",
        },
        brave = { "I can face the dead. Apparently quitting is harder." },
        cautious = { "Keep an eye out for cigarettes, if it is safe." },
        caring = { "Sorry. I know we have bigger problems. I just need a smoke." },
        practical = { "Low priority request: cigarettes, when we find some." },
        stressed = { "I need a cigarette. Badly." },
    },
    ["banter.crowd.yield"] = {
        common = {
            "Get out of my way, %1.",
            "Coming through, %1.",
            "%1, give me a little room.",
            "Move over, %1. I need through.",
            "Excuse me, %1. Let me past.",
        },
        brave = { "Make a hole, %1. Coming through." },
        cautious = { "%1, could you step aside? Just for a second." },
        caring = { "Sorry, %1. Can I squeeze past?" },
        practical = { "%1, clear the path, please." },
        stressed = { "%1! Move!" },
    },
    ["banter.camp.open"] = {
        common = {
            "%1, you holding up all right?",
            "Quiet minute. How are you doing, %1?",
            "%1, tell me something that is not about zombies.",
            "You know, %1, this almost feels like a normal evening.",
            "%1, what is the first thing you would do if this ended tomorrow?",
            "I keep forgetting what ordinary conversation sounds like. Help me out, %1.",
            "%1, sit with me a minute. The work can wait that long.",
            "Long day, %1. At least we made it back together.",
        },
        brave = { "%1, when this is over, I am buying the first round." },
        cautious = { "Doors are shut, windows are clear. We can breathe for a minute, %1." },
        caring = { "%1, you have been quiet. I wanted to make sure you are okay." },
        practical = { "Supplies are counted and the place is standing. How are you, %1?" },
    },
    ["banter.camp.reply"] = {
        common = {
            "Still here. That counts for a lot, %1.",
            "Ask me again after coffee, %1. Real coffee.",
            "Honestly? Better now that somebody asked.",
            "I was thinking about home. The old one, not this place.",
            "Tired, but not ready to give up. Not even close.",
            "Something not about zombies? I miss terrible television.",
            "If this ends tomorrow, I sleep until next week.",
            "We made it back. I will take that victory, %1.",
        },
        brave = { "Doing fine, %1. The dead should be worried about us." },
        cautious = { "I will feel better after one more check of the windows." },
        caring = { "I am all right. You can lean on me too, you know." },
        practical = { "Fed, dry, and breathing. That is a good day now." },
    },
    ["banter.meeting.hello"] = {
        common = {
            "Hey there. I am %1. We are not looking for trouble.",
            "Hello. Easy now. My name is %1.",
            "Hi. Another living face is good to see. I am %1.",
            "Hey. We can keep our distance. Just wanted to say hello.",
            "Hello there. You alone out here?",
            "Easy. Friendly voice, friendly hands. I am %1.",
            "Hi. Been a while since I met somebody who could answer back.",
            "Hey, survivor. Good to meet you while we are both still breathing.",
        },
        brave = { "Hey! Nice to meet somebody with a pulse. I am %1." },
        cautious = { "Hello. Stay where I can see you, please. I am %1." },
        caring = { "Hi. Are you hurt? I am %1." },
        practical = { "Hello. We can talk before anybody makes a bad decision. I am %1." },
    },
    ["banter.meeting.reply"] = {
        common = {
            "Hi, %1. I was starting to think everyone was gone.",
            "Good to meet you, %1. I do not want trouble either.",
            "Hello. Been a rough few days, but I am still here.",
            "Hey. Thanks for saying something before pointing a weapon.",
            "Hi there. I have not heard a friendly voice in a while.",
            "Good to meet you. Let us both keep this calm.",
            "Hello, %1. Nice to remember people can still be polite.",
            "Hey. Alive, tired, and glad to see company.",
        },
        brave = { "Good to meet you, %1. I can handle myself." },
        cautious = { "Hello, %1. I will keep my hands where you can see them." },
        caring = { "Hi, %1. I am okay. Thank you for asking." },
        practical = { "Hello, %1. Talking first works for me." },
    },
    ["banter.distraction.self"] = {
        common = {
            "HEY! Is that a Spiffo's coupon on the ground?!",
            "Look over there! A mule in a hospital gown!",
            "Attention! Free brains at the Muldraugh water tower!",
            "Behind you! It's the tax man!",
            "Your fly's down! ...Worth a shot.",
            "Excuse me! I believe you dropped your dignity!",
        },
        brave = { "Over there! Your mother, and she's disappointed!" },
        cautious = { "Look, a way out! For you! Over there! Please!" },
        caring = { "Hey! Somebody out there misses you! Go find them!" },
        practical = { "Distraction attempt one: look left. No? Noted." },
        stressed = { "LOOK! SOMETHING! ANYTHING! OVER THERE!" },
    },
    ["banter.distraction.ally"] = {
        common = {
            "HEY, UGLY! Over here! I taste better!",
            "Leave 'em be! I'm the one wearing cologne!",
            "Yoo-hoo! Fresh meat, other direction!",
            "Over here, you walking rash! Come get me instead!",
        },
    },
    ["banter.distraction.verdict"] = {
        common = {
            "Tough crowd.",
            "They never fall for it.",
            "Didn't think so.",
            "Worth a try. Wasn't worth much.",
        },
    },
    ["banter.refusal.immediate_count"] = {
        common = {
            "That's three of them. I'm not going in there.",
            "Too many right on top of me. I'm backing out.",
            "They're already in reach. No. I'm coming back.",
            "I can't take that many at arm's length.",
        },
        brave = { "That's not a fight. That's a pile-on. I'm out." },
        cautious = { "They're too close already. We need another way." },
        caring = { "I won't make you drag me out of that crowd." },
        practical = { "Three in striking distance. Bad trade. Backing off." },
    },
    ["banter.refusal.directional_pressure"] = {
        common = {
            "Too much coming from that side. I'm pulling back.",
            "That whole line is pushing this way. Not safe.",
            "Pressure's building too fast. I'm giving ground.",
            "I can't hold that approach. Coming back.",
        },
        brave = { "They've got the weight on that side. I'll reset." },
        cautious = { "That side is folding in. We need room now." },
        caring = { "They're pushing through. Stay back with me." },
        practical = { "Too much pressure on one side. Repositioning." },
    },
    ["banter.refusal.close_pressure"] = {
        common = {
            "More close than I can handle. I'm backing off.",
            "I don't have room for all of them.",
            "They're crowding my reach. I need distance.",
            "Too many in my face. Give me room.",
        },
        brave = { "I can take a few, not the whole doorway. Moving." },
        cautious = { "They're inside my safe distance. I'm leaving it." },
        caring = { "I can't cover anyone from inside that crush." },
        practical = { "Their numbers exceed my reach. Creating distance." },
    },
    ["banter.refusal.occupied_sectors"] = {
        common = {
            "They're coming from three sides. I'm falling back.",
            "Too many angles. I can't hold this spot.",
            "They've got every side of me. Moving out.",
            "No clean front anymore. I'm coming back.",
        },
        brave = { "I don't mind a fight. I mind three fronts. Backing off." },
        cautious = { "They're on every side. I knew this spot was bad." },
        caring = { "I can't watch all those angles and watch you too." },
        practical = { "Three occupied sectors. Position's gone." },
    },
    ["banter.refusal.internal_risk"] = {
        common = {
            "I'm not steady enough for this. Not right now.",
            "Something's off. I need a second before I fight.",
            "I'm too worn down to make that safe.",
            "I don't have a clean fight in me. Backing off.",
        },
        brave = { "I can force it, but I won't win it like this." },
        cautious = { "I'm not right. I need to settle before we go in." },
        caring = { "I need a breath. I don't want to become your problem." },
        practical = { "Readiness is too low. Resetting before contact." },
    },
    ["banter.refusal.escape_danger"] = {
        common = {
            "That way out is worse than staying put. I'm not committing.",
            "The exit's covered. I need another route.",
            "I can get in, but not back out safely.",
            "That retreat path is hot. Not going yet.",
        },
        brave = { "I'll fight forward when I know I can come back." },
        cautious = { "The way back is crawling. We need another exit." },
        caring = { "If I go there, you can't reach me. No." },
        practical = { "Withdrawal route is compromised. Holding here." },
    },
    ["banter.refusal.footing"] = {
        common = {
            "I can't get my feet under me. I'm backing off.",
            "Bad footing. I'm not fighting from here.",
            "I keep getting tangled up. Give me clear ground.",
            "No room to plant my feet. Moving.",
        },
        brave = { "Put me on clear ground and I'll take them." },
        cautious = { "I'm boxed in by the ground itself. Backing away." },
        caring = { "I can't keep anyone safe while I'm tripping over this." },
        practical = { "Footing's compromised. Relocating." },
    },
    ["banter.refusal.encircled"] = {
        common = {
            "They're all round me. I'm coming back.",
            "I'm surrounded. Breaking out now.",
            "They've closed the circle. I'm not staying in it.",
            "No front, no flank, just teeth. I'm leaving.",
        },
        brave = { "They got around me. Fine. I break out first." },
        cautious = { "They're everywhere. I'm coming back, right now." },
        caring = { "I'm surrounded. Don't come in after me." },
        practical = { "Encircled. Position lost. Withdrawing." },
    },
    ["banter.refusal.no_escape"] = {
        common = {
            "No way out of that room. Not doing it.",
            "That's a dead end. I'm not walking into it.",
            "I don't see an exit. We need another plan.",
            "One door in and no way back. No.",
        },
        brave = { "Give me an exit and I'll go. Not before." },
        cautious = { "No escape route. Absolutely not." },
        caring = { "If I go in there, you can't get me out." },
        practical = { "Zero exits. The approach is rejected." },
    },
    ["banter.refusal.indoors"] = {
        common = {
            "Not in here. Too tight.",
            "I need more room than this. Backing out.",
            "Walls this close turn one mistake into a grave.",
            "Too cramped to fight clean. I'm moving.",
        },
        brave = { "Outside, I'll take them. In this box, no." },
        cautious = { "It's too tight in here. I don't like this at all." },
        caring = { "There's no room to pull each other clear in here." },
        practical = { "Interior spacing is bad. Taking it outside." },
    },
    ["banter.refusal.health"] = {
        common = {
            "I'm in no state for this.",
            "I'm hurt. Another fight can wait.",
            "I won't last through that in this condition.",
            "Not with these wounds. I'm pulling back.",
        },
        brave = { "I'm still standing, but I won't waste what's left." },
        cautious = { "I'm already hurt. I'm not making it worse." },
        caring = { "I need help before I can help anyone in there." },
        practical = { "Health's too low for another exchange." },
    },
    ["banter.refusal.unarmed"] = {
        common = {
            "I've got nothing to fight with. I'm not going in.",
            "Bare hands against that? No chance.",
            "I need a weapon before I take this on.",
            "Not armed, not ready. I'm backing off.",
        },
        brave = { "Give me something with an edge, then ask again." },
        cautious = { "I don't even have a weapon. No." },
        caring = { "Going in empty-handed only gives you someone else to save." },
        practical = { "No weapon. Engagement isn't viable." },
    },
    ["banter.refusal.weapon_condition"] = {
        common = {
            "My axe is about done. You want this?",
            "This weapon won't survive that fight.",
            "One more hard hit and this thing's finished.",
            "My weapon's failing. I need another one.",
        },
        brave = { "I'll finish it when I've got steel that will last." },
        cautious = { "This thing's nearly broken. I'm not trusting my life to it." },
        caring = { "If my weapon breaks in there, you have to come get me." },
        practical = { "Weapon condition is critical. Replacing it first." },
    },
    ["banter.refusal.ammo_dry"] = {
        common = {
            "I'm dry. Give me a second.",
            "Empty. I need to reload before I move in.",
            "No rounds left. I'm backing off.",
            "Gun's dry. This isn't the time to bluff.",
        },
        brave = { "I'm empty, not stupid. Cover me while I reload." },
        cautious = { "No ammunition. I'm not going any closer." },
        caring = { "I'm dry. Stay behind me while I sort it out." },
        practical = { "Magazine empty. Disengaging to reload." },
    },
    ["banter.refusal.stamina"] = {
        common = {
            "I've got nothing left. Not yet.",
            "I can't swing again and still get away.",
            "I'm spent. I need air before I go back in.",
            "No breath, no fight. I'm falling back.",
        },
        brave = { "Give me one breath and I'll be dangerous again." },
        cautious = { "I'm exhausted. I have to stop before they catch me." },
        caring = { "I'm out of breath. Don't risk yourself waiting on me." },
        practical = { "Endurance reserve is gone. Recovering first." },
    },
    ["banter.refusal.risk_score"] = {
        common = {
            "This is turning bad. I'm pulling back.",
            "I don't like the odds anymore. Coming back.",
            "Too much is wrong at once. I'm not committing.",
            "That fight doesn't add up. I'm moving out.",
        },
        brave = { "Bad odds are one thing. These are worse. Resetting." },
        cautious = { "Everything about this feels wrong. I'm backing away." },
        caring = { "This isn't worth losing someone over. I'm coming back." },
        practical = { "Overall risk is too high. Withdrawing." },
    },
    ["banter.idle.first"] = {
        common = {
            "If you're waiting for a sign, this is it. It says 'beans'.",
            "Take your time. The zombies sure are.",
            "I'll just stand here and age, then.",
            "Is this a strategy, or are we lost?",
            "Mamaw could shell a bushel of beans in the time you've been standing there.",
            "Waiting's a skill too. You're maxing it out.",
        },
        brave = { "Standing still makes me itch. Point me at something." },
        cautious = { "Quiet is good. Quiet is fine. I'll keep an eye out." },
        caring = { "You all right? You've gone real quiet on me." },
        practical = { "If we're staying, I could be checking the doors." },
    },
    ["banter.idle.second"] = {
        common = {
            "Ten minutes. I've named every fly in this room.",
            "I'm starting to think you're a very lifelike statue.",
            "If we're waiting, I'm getting my reps in. In my head.",
            "Knox County's longest staring contest. You're winning.",
        },
    },
    ["banter.idle.vehicle"] = {
        common = {
            "Engine's not gonna fix itself. Neither is my mood.",
            "Are we parked, or are we thinking about being parked?",
            "Nice car. Nicer when it moves.",
            "I could walk faster than this. Sitting down.",
        },
    },
}

-- Room definition names (Build 42 Distributions) grouped into one set of lines.
local ROOM_GROUPS = {
    policestorage = "police", policelocker = "police",
    prisoncells = "prison",
    church = "church",
    bar = "bar",
    liquorstore = "liquor",
    whiskeybottling = "whiskey",
    brewery = "brewery",
    classroom = "school", elementaryschool = "school",
    library = "library",
    gunstore = "gunstore",
    pharmacy = "pharmacy",
    hospitalroom = "hospital", medical = "hospital",
    morgue = "morgue",
    dentist = "dentist",
    spiffo_dining = "spiffos", spiffoskitchen = "spiffos",
    jayschicken_dining = "jays",
    gigamart = "grocery", grocery = "grocery",
    gasstore = "gas", fossoil = "gas",
    mechanic = "garage",
    firestorage = "firehouse",
    armystorage = "army",
    theatre = "theatre",
    bowlingalley = "bowling",
    stripclub = "stripclub",
    laboratory = "lab",
    motelroom = "motel",
    laundry = "laundry",
    gym = "gym",
    musicstore = "music",
    bookstore = "books",
    zippeestore = "zippee",
}

-- First-visit remarks. `professions` lines replace the common ones when the
-- speaker used to work in a place like this.
local PLACE_LINES = {
    police = {
        common = {
            "Evidence locker. Somebody's finally getting away with it.",
            "The coffee's still in the pot. Nobody's that brave.",
            "Wanted posters. Most of these fellas are walking around dead now. Still wanted.",
            "The sign says 'Serve and Protect'. Somebody should tell the sign.",
        },
        professions = {
            policeofficer = {
                "Twelve years I signed for everything in this room. Look at it now.",
                "My old desk's through there. Don't touch the stapler. It's evidence.",
            },
            securityguard = { "Real cops. I used to wave at these guys from the mall." },
        },
    },
    prison = {
        common = {
            "Funny. Everybody in here's finally free.",
            "Three meals a day and a lock on the door. Doesn't sound so bad anymore.",
            "Somebody scratched a calendar in the wall. They stopped in July.",
            "Cells kept people in. Right now I'd settle for keeping things out.",
        },
        professions = {
            policeofficer = { "I booked half the county into these cells. Now look who's visiting." },
        },
    },
    church = {
        common = {
            "Pastor said the end was coming. Nobody asked for details.",
            "Pews are still warm. That's not a good sign.",
            "If there's a collection plate, it's the only thing in Kentucky still full.",
            "Say a word if you've got one. I ran out in July.",
        },
        caring = { "Mind your language in here. Even now." },
    },
    bar = {
        common = {
            "Last call was in July. Nobody told the regulars.",
            "Jukebox is out. Small mercies.",
            "Tab's still open. I'm not paying it.",
            "That barstool's got a dent shaped like a man. He's not coming back for it.",
        },
    },
    liquor = {
        common = {
            "Kentucky's pharmacy. Open all hours now.",
            "Every bottle's a painkiller if you believe hard enough.",
            "Somebody got here first. Somebody always gets here first.",
            "Grab the cheap stuff. The good stuff makes you brave.",
        },
    },
    whiskey = {
        common = {
            "Kentucky's finest. I'd weep, but it'd waste water.",
            "Barrels as far as you can see. Heaven's got a waiting room.",
            "Forty years in oak. Shame to drink it now. Shame not to.",
            "Smell that? That's the state flower.",
        },
    },
    brewery = {
        common = {
            "Vats of beer and nobody to drink them. The real tragedy of the Knox Event.",
            "Warm beer is still beer. Don't let anybody tell you different.",
            "This place smells like every bad decision I made before '93.",
            "If the world ends, at least it ended here.",
        },
    },
    school = {
        common = {
            "Pop quiz. Capital of Kentucky? Wrong. It's Frankfort. It's always Frankfort.",
            "Somebody's still got a hall pass. Hope it covers the apocalypse.",
            "Chalkboard says 'Test on Monday'. Test's cancelled, kids.",
            "Always hated these little chairs. Now I hate them more.",
        },
    },
    library = {
        common = {
            "Overdue since July. The fine's gotta be astronomical.",
            "Quiet in here. Library quiet, not dead quiet. I think.",
            "Every book on surviving is checked out. Figures.",
            "The librarian would shush the zombies. I'd pay to see it.",
        },
    },
    gunstore = {
        common = {
            "Second Amendment's still standing. The rest of us, less so.",
            "Empty racks. Everybody had the same idea, just faster.",
            "A gun shop in Kentucky with no guns left. Now I've seen everything.",
            "Loud is the enemy. Remember that before you fall in love in here.",
        },
        professions = {
            veteran = { "Army taught me to count rounds. This place teaches you to count what's missing." },
        },
    },
    pharmacy = {
        common = {
            "Somebody cleaned out the good stuff. The vitamins survived. Of course.",
            "Pharmacist's still in the back, I bet. Don't check.",
            "Aspirin's aspirin. Grab it.",
            "Prescriptions for the whole county. Most of them won't need it now.",
        },
        professions = {
            doctor = { "Check the expiry dates. Then ignore them if you have to." },
            nurse = { "Antibiotics first, then bandages, then anything that says 'extra strength'." },
        },
    },
    hospital = {
        common = {
            "Hospitals went first. Everybody came here to get better.",
            "Don't look in the beds. Just don't.",
            "Visiting hours are over. Permanently.",
            "Smell of bleach and worse. Let's be quick.",
        },
        professions = {
            doctor = { "Triage tags on the floor. Red, red, red. We never had enough hands." },
            nurse = { "Double shifts in this wing. I still dream about the call buttons." },
        },
    },
    morgue = {
        common = {
            "Guess the staff went home early. Then came back.",
            "The cold room's warm now. That's not how it's supposed to work.",
            "Everybody in here was dead before it was cool.",
            "Toe tags. At least somebody got a name.",
        },
        professions = {
            doctor = { "Tags on the toes. We used to be so organized." },
            nurse = { "We wheeled them down here one at a time. Then we stopped counting." },
        },
    },
    dentist = {
        common = {
            "Nobody wants to be here. Not even now.",
            "That drill sound still gives me chills. Just the memory.",
            "Lollipops by the door. The good dentists had lollipops.",
            "Floss daily. Doctor's orders. Doctor's gone, but the order stands.",
        },
    },
    spiffos = {
        common = {
            "Spiffo's. Every meal came with a free existential crisis.",
            "Spiffo's still smiling. Somebody should stop him.",
            "Kids' meals and a mascot costume. This place was already a horror show.",
            "I had my tenth birthday at one of these. Nobody's cake survived.",
        },
        professions = {
            chef = { "I wouldn't feed this grill to a raccoon. And I've fed raccoons." },
            burgerflipper = { "I worked a fryer like this for three summers. I can still hear the timer." },
        },
    },
    jays = {
        common = {
            "Jay's Chicken. Finger-licking and then some.",
            "Still smells like fry oil. The last good smell in Knox County.",
            "Bucket's empty. Story of '93.",
            "I'd kill for a biscuit. Carefully. Quietly.",
        },
        professions = {
            chef = { "Twelve herbs and spices my foot. It was salt and prayer." },
            burgerflipper = { "Same fryer, same grease, different bird. I know this kitchen." },
        },
    },
    grocery = {
        common = {
            "Aisle five, canned hope. Mostly gone.",
            "Shopping carts everywhere. Everybody left in a hurry.",
            "Dairy section. Hold your breath and keep walking.",
            "Price check on everything. Everything's free now. Everything's gone.",
        },
    },
    gas = {
        common = {
            "Gas, snacks, and a bathroom key on a hubcap. Civilization.",
            "Pumps are dry, candy's stale, still better than most places.",
            "Somebody bought a lottery ticket here. Bad timing.",
            "Beef jerky lasts forever. It's about to prove it.",
        },
        professions = {
            mechanics = { "Somebody left the air pump running. Old habits." },
        },
    },
    garage = {
        common = {
            "Somebody left a car on the lift. Rude.",
            "Smells like oil and regret. Good tools, though.",
            "Every garage has a calendar on the wall. This one's stuck on July.",
            "If there's a working battery in here, I want it.",
        },
        professions = {
            mechanics = { "Torque wrench, good sockets, and nobody took the creeper. Heaven." },
        },
    },
    firehouse = {
        common = {
            "Firehouse. Brave folks. Bad luck.",
            "The engine's still here. They never made it out.",
            "The pole's still there. Don't tempt me.",
            "Everybody runs from fire. These folks ran toward it. Toward everything.",
        },
        professions = {
            fireofficer = { "My crew's lockers are down the hall. I'm not opening them." },
        },
    },
    army = {
        common = {
            "Army surplus. Mostly surplus now.",
            "Ration boxes. They taste like duty.",
            "Somebody stocked this for a war. Wrong war.",
            "If the army couldn't hold Knox, I'm not sure a shelf of helmets will.",
        },
        professions = {
            veteran = { "Smells like basic training. I didn't miss it." },
        },
    },
    theatre = {
        common = {
            "Last picture show in Knox County. Two thumbs down.",
            "Popcorn machine's still full. Stale, but full.",
            "Everybody loved a zombie movie. Right up until July.",
            "Quiet in the back row. Always was.",
        },
    },
    bowling = {
        common = {
            "Strike. Spare. Everybody else.",
            "Rental shoes. The true horror.",
            "Scoreboard still shows the last game. Somebody was winning.",
            "League night's cancelled. Forever.",
        },
    },
    stripclub = {
        common = {
            "I'm not saying anything. I'm just... not saying anything.",
            "Well. We're adults. Let's be adults and keep moving.",
            "Cash still in the tip jar. Nobody's that desperate. Yet.",
            "Mama would want me to cover my eyes. Mama's not here.",
        },
    },
    lab = {
        common = {
            "Whatever started this started somewhere. This room looks guilty.",
            "Biohazard stickers. Great. Love that for us.",
            "Somebody was running tests. The test ran them.",
            "Don't touch anything that glows. Or hums. Or breathes.",
        },
    },
    motel = {
        common = {
            "No vacancy. Plenty of vacancy.",
            "Ice machine's broken. Some things never change.",
            "Somebody hung the 'Do Not Disturb' sign. Respect it.",
            "Cheap sheets make good bandages. Just saying.",
        },
    },
    laundry = {
        common = {
            "Somebody's still waiting on their spin cycle.",
            "Warm socks. Clean socks. I could cry.",
            "Coin-op. I've got coins. Nothing to feed.",
            "Lost-and-found box. Everybody's lost now.",
        },
    },
    gym = {
        common = {
            "Membership expired. So did the members.",
            "No pain, no gain. Plenty of pain lately.",
            "Treadmills. Running in place. We've all been doing that since July.",
            "Leg day's every day now. Running counts.",
        },
        professions = {
            fitnessinstructor = { "I used to yell 'one more rep' in here. Now I yell 'run'." },
        },
    },
    music = {
        common = {
            "A guitar with a busted string. Still more hopeful than the radio.",
            "Bluegrass section. Somebody grab a banjo. Or don't.",
            "Records don't need power. Just a turntable and faith.",
            "If I find a harmonica, you'll never hear the end of it.",
        },
    },
    books = {
        common = {
            "Self-help section's picked clean. Of course it is.",
            "Mystery novels. I know who did it. Everybody did it.",
            "Maps and field guides. Grab those before the romance.",
            "Smell of old paper. Almost like nothing happened.",
        },
    },
    zippee = {
        common = {
            "Zippee Market. Zip in, zip out, like the jingle said.",
            "The hot dog roller's still rolling. No, it isn't. I just wish it was.",
            "Slushie machine. Blue flavor. A mystery forever.",
            "Twenty-four hours, seven days. They meant it.",
        },
    },
}

local VOICE_KEYS = { "common", "brave", "cautious", "caring", "practical", "stressed" }

local poolsRegistered = false
local function registerPools()
    if poolsRegistered then return end
    if not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return end
    for topic, specification in pairs(POOLS) do SC.Dialogue.register(topic, specification) end
    for group, entry in pairs(PLACE_LINES) do
        local specification = {}
        for _, key in ipairs(VOICE_KEYS) do specification[key] = entry[key] end
        SC.Dialogue.register("banter.place." .. group, specification)
        for profession, lines in pairs(entry.professions or {}) do
            SC.Dialogue.register("banter.place." .. group .. "." .. profession, { common = lines })
        end
    end
    poolsRegistered = true
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local function freshParty()
    return {
        lastFlavorAt = -math.huge,
        lastDistractionAt = -math.huge,
        lastRefusalAt = -math.huge,
        lastPlaceAt = -math.huge,
        lastJokeAt = -math.huge,
        idle = nil,
        placeKeys = {},
        placeKeyCount = 0,
        exchange = nil,
        metPairs = {},
        metPairCount = 0,
        campPairs = {},
        campPairCount = 0,
        lastCampConversationAt = -math.huge,
        lastInteriorAt = -math.huge,
        interiorCursor = 0,
    }
end

local party = freshParty()
local actors = setmetatable({}, { __mode = "k" })

local function actorState(actor)
    local state = actors[actor]
    if not state then
        state = { seenPlaces = {} }
        actors[actor] = state
    end
    return state
end

local function commandState(actor, supplied)
    if type(supplied) == "table" then return supplied end
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return {}
end

local function enabled()
    return U() ~= nil and U().config("banterEnabled") ~= false
end

-- Chance in percent. ZombRand in game; a stable hash of actor and second in
-- the headless harness.
local function roll(percent, actor, current)
    percent = tonumber(percent) or 0
    if percent >= 100 then return true end
    if percent <= 0 then return false end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, 100)
        if ok and tonumber(value) then return tonumber(value) < percent end
    end
    local hash = U().stableHash(tostring(U().idOf(actor)) .. ":"
        .. tostring(math.floor((tonumber(current) or 0) / 1000)))
    return math.abs(tonumber(hash) or 0) % 100 < percent
end

local function speak(actor, topic, commands, arguments, options)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    registerPools()
    local settings = type(options) == "table" and options or {}
    settings.state = commands
    local ok, spoken = pcall(SC.Dialogue.say, actor, topic, nil, arguments, settings)
    return ok and spoken == true
end

local function lastSpokenAt(actor)
    if SC.Dialogue and type(SC.Dialogue.lastSpokenAt) == "function" then
        return tonumber(SC.Dialogue.lastSpokenAt(actor))
    end
    return nil
end

local function calm(snapshot)
    if type(snapshot) ~= "table" then return true end
    if (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) > 0 then return false end
    if (tonumber(snapshot.immediateCount) or 0) > 0 then return false end
    if (tonumber(snapshot.pressure) or 0) > 0 then return false end
    local playerState = snapshot.player
    if type(playerState) == "table" and (tonumber(playerState.danger) or 0) > 0 then return false end
    return true
end

local function recordSnapshot(record)
    local runtime = type(record) == "table" and record.runtime or nil
    if type(runtime) ~= "table" then return nil end
    return type(runtime.senses) == "table" and runtime.senses.current or runtime.snapshot
end

local function professionOf(commands)
    local profile = type(commands) == "table" and commands.personalityProfile or nil
    local value = type(profile) == "table" and profile.profession or nil
    if value == nil then return nil end
    value = string.lower(tostring(value))
    value = string.match(value, "[^:%.]+$") or value
    return (string.gsub(value, "[^%w]", ""))
end

-- A recruited, calm, idle companion near the player that has not just spoken.
local function available(record, player, current, radius)
    local actor = type(record) == "table" and record.actor or nil
    local utility = U()
    if actor == nil or not utility.isValidActor(actor) or utility.isDead(actor) then return nil end
    local commands = commandState(actor)
    if commands.recruited ~= true then return nil end
    if not calm(recordSnapshot(record)) then return nil end
    if not utility.sameFloor(actor, player) or utility.distance(actor, player) > radius then
        return nil
    end
    if SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) ~= nil then return nil end
    local spokenAt = lastSpokenAt(actor)
    if spokenAt and current - spokenAt < config("banterSpeakerQuietMs", 15000) then return nil end
    return commands
end

local budgetAllows

local function firstName(actor)
    local name = tostring(U().nameOf(actor) or "")
    return string.match(name, "^(%S+)") or "friend"
end

local function pairKey(first, second)
    local firstId, secondId = tostring(U().idOf(first)), tostring(U().idOf(second))
    if secondId < firstId then firstId, secondId = secondId, firstId end
    return firstId .. "|" .. secondId
end

local function rememberPair(mapName, countName, key, current, limit)
    local map = party[mapName]
    if map[key] ~= nil then map[key] = current return end
    if party[countName] >= limit then
        party[mapName], party[countName] = {}, 0
        map = party[mapName]
    end
    map[key] = current
    party[countName] = party[countName] + 1
end

local function recordForActor(records, actor)
    for _, record in ipairs(records or {}) do
        if type(record) == "table" and record.actor == actor then return record end
    end
    return nil
end

local function freeSurvivor(record, current)
    local actor = type(record) == "table" and record.actor or nil
    local utility = U()
    if not actor or not utility.isValidActor(actor) or utility.isDead(actor)
        or not calm(recordSnapshot(record)) then return nil end
    if SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) ~= nil then return nil end
    if SC.Positioning and type(SC.Positioning.activeConversation) == "function"
        and SC.Positioning.activeConversation(actor) ~= nil then return nil end
    local spokenAt = lastSpokenAt(actor)
    if spokenAt and current - spokenAt < config("banterSpeakerQuietMs", 15000) then return nil end
    return commandState(actor)
end

local function faceConversation(first, second, action, firstEmote, secondEmote)
    if SC.Positioning and type(SC.Positioning.beginConversation) == "function" then
        pcall(SC.Positioning.beginConversation, first, second,
            { action = action, emote = firstEmote })
        pcall(SC.Positioning.beginConversation, second, first,
            { action = action, emote = secondEmote })
        return
    end
    U().move(first, "walk", { action = "face_conversation", target = second,
        socialMovement = true, stableFacing = true })
    U().move(second, "walk", { action = "face_conversation", target = first,
        socialMovement = true, stableFacing = true })
end

local function beginExchange(first, second, openTopic, replyTopic,
        firstCommands, secondCommands, current, kind)
    if not speak(first, openTopic, firstCommands, { firstName(second) }, {
        salt = kind .. ":open:" .. pairKey(first, second) .. ":" .. tostring(current),
    }) then return false, "conversation_speech_rejected" end
    faceConversation(first, second, kind, kind == "meeting" and "wave" or "yes", "yes")
    party.exchange = {
        first = first, second = second, replyTopic = replyTopic,
        secondCommands = secondCommands, nextAt = current
            + config("companionConversationReplyMs", 2800),
        expiresAt = current + config("companionConversationTimeoutMs", 9000),
        kind = kind,
    }
    party.lastFlavorAt = current
    return true, openTopic
end

local function exchangePulse(records, current)
    local exchange = party.exchange
    if type(exchange) ~= "table" then return false, "no_exchange", false end
    if current >= (exchange.expiresAt or 0) then
        party.exchange = nil
        return false, "conversation_expired", false
    end
    local firstRecord = recordForActor(records, exchange.first)
    local secondRecord = recordForActor(records, exchange.second)
    if not firstRecord or not secondRecord or not calm(recordSnapshot(firstRecord))
        or not calm(recordSnapshot(secondRecord)) or U().isDead(exchange.first)
        or U().isDead(exchange.second) then
        party.exchange = nil
        return false, "conversation_interrupted", false
    end
    if current < (exchange.nextAt or 0) then return false, "conversation_waiting", true end
    local spoken = speak(exchange.second, exchange.replyTopic, exchange.secondCommands,
        { firstName(exchange.first) }, {
            salt = exchange.kind .. ":reply:" .. pairKey(exchange.first, exchange.second)
                .. ":" .. tostring(current),
        })
    local topic = exchange.replyTopic
    party.exchange = nil
    if not spoken then return false, "conversation_reply_rejected", false end
    party.lastFlavorAt = current
    return true, topic, false
end

local function greetingPulse(player, records, current)
    if not budgetAllows(current) then return false, "flavor_budget" end
    local radius = config("meetingGreetingDistance", 6)
    local playerRadius = config("meetingGreetingPlayerDistance", 14)
    for _, firstRecord in ipairs(records or {}) do
        local first = firstRecord.actor
        local firstCommands = available(firstRecord, player, current, playerRadius)
        if firstCommands then
            for _, secondRecord in ipairs(records or {}) do
                local second = secondRecord.actor
                local secondCommands = second ~= first and freeSurvivor(secondRecord, current) or nil
                if secondCommands and secondCommands.recruited ~= true
                    and U().sameFloor(first, second) and U().distance(first, second) <= radius
                    and U().canSee(first, second)
                    and not (SC.Factions and type(SC.Factions.isHostileBetween) == "function"
                        and SC.Factions.isHostileBetween(first, second, player)) then
                    local key = pairKey(first, second)
                    if party.metPairs[key] == nil then
                        local spoken, topic = beginExchange(first, second,
                            "banter.meeting.hello", "banter.meeting.reply",
                            firstCommands, secondCommands, current, "meeting")
                        if spoken then
                            rememberPair("metPairs", "metPairCount", key, current,
                                math.max(16, math.floor(config("meetingGreetingMemoryLimit", 128))))
                            return true, topic
                        end
                        return false, topic
                    end
                end
            end
        end
    end
    return false, "no_new_survivor_nearby"
end

local function atCamp(actor)
    return SC.BaseLife and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(actor) == true
end

local function campConversationPulse(player, records, current)
    if current - party.lastCampConversationAt
        < config("campConversationPartyCooldownMs", 60000) then
        return false, "camp_conversation_cooldown"
    end
    if not budgetAllows(current) then return false, "flavor_budget" end
    local radius = config("campConversationDistance", 8)
    local actorCooldown = config("campConversationActorCooldownMs", 180000)
    local candidates = {}
    for _, record in ipairs(records or {}) do
        local commands = available(record, player, current,
            config("meetingGreetingPlayerDistance", 14))
        local moving, movingOk = record.actor and U().call(record.actor, "isMoving")
        if commands and atCamp(record.actor) and not (movingOk and moving == true)
            and current - (actorState(record.actor).lastCampTalkAt or -math.huge)
                >= actorCooldown then
            candidates[#candidates + 1] = { record = record, commands = commands }
        end
    end
    for firstIndex = 1, #candidates do
        for secondIndex = firstIndex + 1, #candidates do
            local first, second = candidates[firstIndex], candidates[secondIndex]
            local firstActor, secondActor = first.record.actor, second.record.actor
            local key = pairKey(firstActor, secondActor)
            local prior = tonumber(party.campPairs[key]) or -math.huge
            if U().sameFloor(firstActor, secondActor)
                and U().distance(firstActor, secondActor) <= radius
                and U().canSee(firstActor, secondActor)
                and current - prior >= config("campConversationPairCooldownMs", 600000) then
                local spoken, topic = beginExchange(firstActor, secondActor,
                    "banter.camp.open", "banter.camp.reply",
                    first.commands, second.commands, current, "camp")
                if spoken then
                    actorState(firstActor).lastCampTalkAt = current
                    actorState(secondActor).lastCampTalkAt = current
                    rememberPair("campPairs", "campPairCount", key, current, 128)
                    party.lastCampConversationAt = current
                    return true, topic
                end
                return false, topic
            end
        end
    end
    return false, "camp_conversation_no_pair"
end

budgetAllows = function(current)
    return current - party.lastFlavorAt >= config("flavorPartySpeechGapMs", 20000)
end

-- Shared with SCTales: one flavor budget and one notion of a free speaker.
function Banter.budgetAllows(current)
    return budgetAllows(tonumber(current) or U().nowMs())
end

function Banter.spendBudget(current)
    party.lastFlavorAt = tonumber(current) or U().nowMs()
end

-- Functional speech for companion traffic. It has its own short cooldown and
-- does not consume the ambient-story budget: the line explains a real order.
function Banter.crowdYield(actor, blocker, current)
    current = tonumber(current) or U().nowMs()
    local own = actorState(actor)
    if current - (tonumber(own.lastCrowdYieldAt) or -math.huge)
        < config("crowdYieldSpeechCooldownMs", 8000) then
        return false, "crowd_yield_speech_cooldown"
    end
    local spoken = speak(actor, "banter.crowd.yield", commandState(actor),
        { firstName(blocker) }, {
            salt = pairKey(actor, blocker) .. ":" .. tostring(current),
        })
    if spoken then own.lastCrowdYieldAt = current end
    return spoken, spoken and "crowd_yield_spoken" or "crowd_yield_speech_rejected"
end

function Banter.availableSpeaker(record, player, current, radius)
    return available(record, player, tonumber(current) or U().nowMs(),
        tonumber(radius) or config("ambientDialogueDistance", 10))
end

function Banter.playerIdleMs(current)
    local idle = party.idle
    if type(idle) ~= "table" then return 0 end
    return math.max(0, (tonumber(current) or U().nowMs()) - (tonumber(idle.since) or 0))
end

-- The persisted flavor bucket (commands.flavor): places a companion has
-- remarked on, stories told, and the day of its last workout. Unknown keys
-- are dropped and both maps stay bounded.
function Banter.normalizeFlavor(value)
    local bucket = { version = 1, placesSeen = {}, storiesTold = {}, lastWorkoutDay = -1 }
    if type(value) ~= "table" then return bucket end
    local count, limit = 0, math.max(0, math.floor(config("placesSeenLimit", 48)))
    for key, seen in pairs(type(value.placesSeen) == "table" and value.placesSeen or {}) do
        if type(key) == "string" and key ~= "" and #key <= 48 and seen == true and count < limit then
            bucket.placesSeen[key] = true
            count = count + 1
        end
    end
    count = 0
    for key, day in pairs(type(value.storiesTold) == "table" and value.storiesTold or {}) do
        day = tonumber(day)
        if type(key) == "string" and key ~= "" and #key <= 48 and day ~= nil and day == day
            and day >= 0 and day < 1000000 and count < 32 then
            bucket.storiesTold[key] = math.floor(day)
            count = count + 1
        end
    end
    local workoutDay = tonumber(value.lastWorkoutDay)
    if workoutDay ~= nil and workoutDay == workoutDay and workoutDay >= -1
        and workoutDay < 1000000 then
        bucket.lastWorkoutDay = math.floor(workoutDay)
    end
    return bucket
end

local checkedFlavor = setmetatable({}, { __mode = "k" })

function Banter.flavor(commands)
    if type(commands) ~= "table" then return nil end
    local bucket = commands.flavor
    if type(bucket) == "table" and checkedFlavor[bucket] then return bucket end
    bucket = Banter.normalizeFlavor(bucket)
    commands.flavor = bucket
    checkedFlavor[bucket] = true
    return bucket
end

-- ---------------------------------------------------------------------------
-- Distraction shouts
-- ---------------------------------------------------------------------------

local function isGrabbed(actor)
    return SC.ZombieAttack ~= nil and type(SC.ZombieAttack.isGrabbed) == "function"
        and SC.ZombieAttack.isGrabbed(actor) == true
end

local function grabbedAllyNear(actor, snapshot)
    if type(snapshot) ~= "table" then return nil end
    local radius = config("distractionAllyRadius", 8)
    for _, ally in ipairs(snapshot.allies or {}) do
        local other = type(ally) == "table" and ally.actor or nil
        if other ~= nil and other ~= actor and isGrabbed(other)
            and U().distance(actor, other) <= radius then
            return other
        end
    end
    return nil
end

local function healthOf(actor, assessment)
    if type(assessment) == "table" and tonumber(assessment.health) then
        return tonumber(assessment.health)
    end
    return tonumber(U().nativeHealth(actor)) or 100
end

local function tryDistraction(actor, commands, assessment, current, mode)
    local own = actorState(actor)
    if healthOf(actor, assessment) < config("distractionMinHealth", 40) then
        return false, "distraction_too_hurt"
    end
    if current < (own.distractionCheckAt or -math.huge) then
        return false, "distraction_check_not_due"
    end
    own.distractionCheckAt = current + config("distractionCheckMs", 4000)
    if current - (own.distractionAt or -math.huge) < config("distractionActorCooldownMs", 60000) then
        return false, "distraction_actor_cooldown"
    end
    if current - party.lastDistractionAt < config("distractionPartyCooldownMs", 20000) then
        return false, "distraction_party_cooldown"
    end
    -- A fresh plea or warning wins; a distraction only fills the gaps.
    local spokenAt = lastSpokenAt(actor)
    if spokenAt and current - spokenAt < config("distractionQuietMs", 3000) then
        return false, "distraction_recently_spoke"
    end
    local chance = mode == "ally" and config("distractionAllyChancePercent", 25)
        or config("distractionChancePercent", 35)
    if not roll(chance, actor, current) then return false, "distraction_not_rolled" end
    local topic = mode == "ally" and "banter.distraction.ally" or "banter.distraction.self"
    if not speak(actor, topic, commands) then return false, "distraction_speech_rejected" end
    own.distractionAt = current
    party.lastDistractionAt = current
    if mode == "self" then
        own.verdictAt = current + config("distractionVerdictDelayMs", 3500)
    end
    return true, topic
end

-- Speech-only explanation for the deterministic overrun decision. Combat calls
-- this once when an autonomous overrun episode begins; the long actor and party
-- cooldowns are deliberately separate from ordinary flavour banter.
function Banter.overrunRefusal(actor, commands, assessment, current, options)
    if not enabled() or actor == nil then return false, "banter_disabled" end
    commands = commandState(actor, commands)
    if commands.recruited ~= true then return false, "banter_not_recruited" end
    if type(assessment) ~= "table" or assessment.overrun ~= true
        or type(assessment.cause) ~= "string" then
        return false, "refusal_cause_missing"
    end
    local topic = "banter.refusal." .. assessment.cause
    if POOLS[topic] == nil then topic = "banter.refusal.risk_score" end
    current = tonumber(current) or U().nowMs()
    options = type(options) == "table" and options or {}
    local reliable = options.reliable == true
    local own = actorState(actor)
    local actorCooldown = reliable
        and config("combatRequestedRefusalActorCooldownMs", 5000)
        or config("combatRefusalActorCooldownMs", 120000)
    if current - (own.refusalAt or -math.huge)
        < actorCooldown then
        return false, "refusal_actor_cooldown"
    end
    local partyCooldown = reliable
        and config("combatRequestedRefusalPartyCooldownMs", 1200)
        or config("combatRefusalPartyCooldownMs", 30000)
    if current - party.lastRefusalAt
        < partyCooldown then
        return false, "refusal_party_cooldown"
    end
    local spokenAt = lastSpokenAt(actor)
    local quiet = reliable and config("combatRequestedRefusalQuietMs", 1000)
        or config("combatRefusalQuietMs", 5000)
    if spokenAt and current - spokenAt < quiet then
        return false, "refusal_recently_spoke"
    end
    local chance = reliable and 100
        or config("combatRefusalChancePercent", 35)
    if not roll(chance, actor, current) then return false, "refusal_not_rolled" end
    if not speak(actor, topic, commands, nil, { salt = assessment.cause }) then
        return false, "refusal_speech_rejected"
    end
    own.refusalAt, own.refusalCause = current, assessment.cause
    party.lastRefusalAt = current
    return true, topic
end

-- Called from a companion's decision beat (and for a grabbed companion from
-- the runtime). Speech only.
function Banter.combatPulse(actor, player, snapshot, commands, assessment, current)
    if not enabled() or actor == nil then return false, "banter_disabled" end
    commands = commandState(actor, commands)
    if commands.recruited ~= true then return false, "banter_not_recruited" end
    current = tonumber(current) or U().nowMs()
    local own = actorState(actor)
    local trouble = isGrabbed(actor)
        or (type(snapshot) == "table" and snapshot.encircled == true)
    if own.verdictAt and current >= own.verdictAt then
        own.verdictAt = nil
        if trouble and roll(config("distractionVerdictChancePercent", 50), actor, current) then
            speak(actor, "banter.distraction.verdict", commands)
        end
    end
    if trouble then return tryDistraction(actor, commands, assessment, current, "self") end
    if grabbedAllyNear(actor, snapshot) then
        return tryDistraction(actor, commands, assessment, current, "ally")
    end
    return false, "banter_no_trouble"
end

function Banter.grabbedPulse(actor, player, snapshot, current)
    return Banter.combatPulse(actor, player, snapshot, nil, nil, current)
end

-- ---------------------------------------------------------------------------
-- Interior state narration
-- ---------------------------------------------------------------------------

local function trait(actor, name)
    if actor == nil or CharacterTrait == nil then return false end
    local ok, native = pcall(function() return CharacterTrait[name] end)
    if not ok then return false end
    if native == nil then return false end
    local value, called = U().call(actor, "hasTrait", native)
    return called and value == true
end

local function nativeInteriorSample(actor)
    local stress = SC.Vitals and type(SC.Vitals.environmentalStress) == "function"
        and SC.Vitals.environmentalStress(actor)
        or U().characterStatValue(actor, "STRESS", 0)
    local nicotine = SC.Vitals and type(SC.Vitals.effectiveNicotineStress) == "function"
        and SC.Vitals.effectiveNicotineStress(actor) or nil
    if nicotine == nil then
        nicotine = SC.Vitals and type(SC.Vitals.nicotineWithdrawal) == "function"
            and SC.Vitals.nicotineWithdrawal(actor)
            or U().characterStatValue(actor, "NICOTINE_WITHDRAWAL", 0)
    end
    return {
        stress = tonumber(stress) or 0,
        panic = tonumber(U().moodleLevel(actor, "PANIC", 0)) or 0,
        nicotine = tonumber(nicotine) or 0,
    }
end

local function interiorEligible(actor, player, commands, current)
    if commands.recruited ~= true or not U().isValidActor(actor) or U().isDead(actor) then
        return false, "interior_not_recruited"
    end
    if player == nil or U().isDead(player) or not U().sameFloor(actor, player)
        or U().distance(actor, player) > config("interiorSpeechDistance", 10) then
        return false, "interior_player_not_nearby"
    end
    if SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) ~= nil then
        return false, "interior_actor_busy"
    end
    local spokenAt = lastSpokenAt(actor)
    if spokenAt and current - spokenAt < config("banterSpeakerQuietMs", 15000) then
        return false, "interior_recently_spoke"
    end
    return true
end

--- Observe engine vitals for speech only. In particular, this never writes
--- commands.stress: relationship stress and environmental STRESS are separate.
function Banter.interiorPulse(actor, player, current, suppliedCommands)
    if not enabled() or actor == nil then return false, "banter_disabled" end
    current = tonumber(current) or U().nowMs()
    local commands = commandState(actor, suppliedCommands)
    local own = actorState(actor)
    local sample = nativeInteriorSample(actor)
    local playerSample = nativeInteriorSample(player)
    sample.playerStress = playerSample.stress
    local prior = own.interiorSample
    own.interiorSample = sample
    if type(prior) ~= "table" then
        own.nicotineArmed = sample.nicotine < config("interiorNicotineThreshold", 0.12)
        return false, "interior_baseline"
    end

    if sample.nicotine <= config("interiorNicotineResetThreshold", 0.04) then
        own.nicotineArmed = true
    end
    local panicThreshold = config("interiorPanicThreshold", 2)
    local topic, chance, diaryKind
    if prior.panic < panicThreshold and sample.panic >= panicThreshold then
        topic, chance, diaryKind = "banter.interior.panic_onset",
            config("interiorPanicChancePercent", 100), "panic"
    elseif prior.panic >= panicThreshold and sample.panic < panicThreshold then
        topic, chance, diaryKind = "banter.interior.panic_recovery",
            config("interiorPanicChancePercent", 100), "panic"
    else
        local actorRise = sample.stress - prior.stress
        local playerRise = playerSample.stress - (tonumber(prior.playerStress) or playerSample.stress)
        if not trait(actor, "DEAF")
            and actorRise >= config("interiorStressRiseThreshold", 0.08)
            and playerRise <= config("interiorPlayerStressRiseTolerance", 0.03) then
            topic, chance, diaryKind = "banter.interior.dread",
                config("interiorDreadChancePercent", 60), "dread"
        elseif trait(actor, "SMOKER") and own.nicotineArmed ~= false
            and prior.nicotine < config("interiorNicotineThreshold", 0.12)
            and sample.nicotine >= config("interiorNicotineThreshold", 0.12) then
            topic, chance, diaryKind = "banter.interior.nicotine",
                config("interiorNicotineChancePercent", 65), "nicotine"
            own.nicotineArmed = false
        end
    end
    if topic == nil then return false, "interior_no_transition" end
    if current - party.lastRefusalAt < config("interiorRefusalPriorityMs", 5000) then
        return false, "interior_refusal_priority"
    end
    if current - (own.interiorSpokenAt or -math.huge)
        < config("interiorActorCooldownMs", 180000) then
        return false, "interior_actor_cooldown"
    end
    if current - party.lastInteriorAt < config("interiorPartyCooldownMs", 45000) then
        return false, "interior_party_cooldown"
    end
    if not budgetAllows(current) then return false, "flavor_budget" end
    local eligible, reason = interiorEligible(actor, player, commands, current)
    if not eligible then return false, reason end
    if not roll(chance, actor, current) then return false, "interior_not_rolled" end
    if not speak(actor, topic, commands, nil, { salt = topic .. ":" .. tostring(current) }) then
        return false, "interior_speech_rejected"
    end
    own.interiorSpokenAt = current
    party.lastInteriorAt = current
    party.lastFlavorAt = current
    if SC.Diary and type(SC.Diary.noteInteriorState) == "function" then
        pcall(SC.Diary.noteInteriorState, actor, diaryKind)
    end
    return true, topic
end

local function interiorPartyPulse(player, records, current)
    local count = #(records or {})
    if count == 0 then return false, "interior_no_companions" end
    party.interiorCursor = (tonumber(party.interiorCursor) or 0) % count + 1
    local record = records[party.interiorCursor]
    if type(record) ~= "table" or record.actor == nil then
        return false, "interior_invalid_record"
    end
    return Banter.interiorPulse(record.actor, player, current)
end

-- ---------------------------------------------------------------------------
-- Idle jokes
-- ---------------------------------------------------------------------------

local function playerBusy(player)
    if type(ISTimedActionQueue) == "table"
        and type(ISTimedActionQueue.isPlayerDoingAction) == "function" then
        local ok, busy = pcall(ISTimedActionQueue.isPlayerDoingAction, player)
        if ok and busy == true then return true end
    end
    local asleep, asleepOk = U().call(player, "isAsleep")
    if asleepOk and asleep == true then return true end
    local aiming, aimingOk = U().call(player, "isAiming")
    return aimingOk and aiming == true
end

local function playerVehicle(player)
    local vehicle, ok = U().call(player, "getVehicle")
    if not ok or vehicle == nil then return nil, false end
    local speed, speedOk = U().call(vehicle, "getCurrentSpeedKmHour")
    return vehicle, speedOk and math.abs(tonumber(speed) or 0) > 1
end

-- Restart the idle clock whenever the player moves, works, sleeps, aims or
-- drives. Returns the idle record and whether the player sits in a vehicle.
local function trackIdle(player, current)
    local x, y, z = U().position(player)
    if x == nil then party.idle = nil return nil, false end
    local vehicle, driving = playerVehicle(player)
    local idle = party.idle
    local moved = idle == nil or math.floor(z or 0) ~= math.floor(idle.z or 0)
        or (x - idle.x) * (x - idle.x) + (y - idle.y) * (y - idle.y) > 0.09
    if moved or driving or playerBusy(player) then
        party.idle = { x = x, y = y, z = z, since = current }
        return nil, vehicle ~= nil
    end
    return idle, vehicle ~= nil
end

local function jokePulse(player, records, current, idle, inVehicle)
    if idle == nil then return false, "idle_player_active" end
    local stillFor = current - idle.since
    local tier
    if idle.firstDone and not idle.secondDone
        and stillFor >= config("idleJokeSecondMs", 600000) then
        tier = "second"
    elseif not idle.firstDone and stillFor >= config("idleJokeFirstMs", 180000) then
        tier = "first"
    end
    if tier == nil then return false, "idle_not_due" end
    if tier == "first" and current - party.lastJokeAt < config("idleJokeRearmMs", 300000) then
        return false, "idle_rearming"
    end
    if not budgetAllows(current) then return false, "flavor_budget" end
    local radius = config("ambientDialogueDistance", 10)
    local best, bestCommands, bestJoked
    for _, record in ipairs(records or {}) do
        local commands = available(record, player, current, radius)
        if commands then
            local joked = actorState(record.actor).jokedAt or -math.huge
            if best == nil or joked < bestJoked then
                best, bestCommands, bestJoked = record.actor, commands, joked
            end
        end
    end
    if best == nil then return false, "idle_no_speaker" end
    local topic = inVehicle and "banter.idle.vehicle" or ("banter.idle." .. tier)
    -- The ten-minute bit becomes a workout once gestures exist (SCGestures):
    -- "If we're waiting, I'm getting my reps in."
    if tier == "second" and not inVehicle and SC.Gestures
        and type(SC.Gestures.requestIdleWorkout) == "function"
        and SC.Gestures.requestIdleWorkout(best, current) == true then
        topic = "gestures.workout.idle"
    end
    if not speak(best, topic, bestCommands) then return false, "idle_speech_rejected" end
    if tier == "first" then idle.firstDone = true else idle.secondDone = true end
    party.lastJokeAt = current
    party.lastFlavorAt = current
    actorState(best).jokedAt = current
    return true, topic
end

-- ---------------------------------------------------------------------------
-- Place commentary
-- ---------------------------------------------------------------------------

local function buildingOf(square)
    local building, ok = U().call(square, "getBuilding")
    if ok then return building end
    return nil
end

local function rememberPlace(key)
    if party.placeKeys[key] then return end
    if party.placeKeyCount >= config("placeCommentMemoryLimit", 256) then
        party.placeKeys, party.placeKeyCount = {}, 0
    end
    party.placeKeys[key] = true
    party.placeKeyCount = party.placeKeyCount + 1
end

-- A companion remembers the kinds of places it has remarked on in its saved
-- flavor bucket, so a save and reload does not repeat them.
local function placeSeen(actor, commands, group)
    if actorState(actor).seenPlaces[group] then return true end
    local flavor = Banter.flavor(commands)
    return type(flavor) == "table" and flavor.placesSeen[group] == true
end

local function rememberSeenPlace(actor, commands, group)
    actorState(actor).seenPlaces[group] = true
    local flavor = Banter.flavor(commands)
    if type(flavor) ~= "table" or flavor.placesSeen[group] then return false end
    local count = 0
    for _ in pairs(flavor.placesSeen) do count = count + 1 end
    if count >= math.max(0, math.floor(config("placesSeenLimit", 48))) then return false end
    flavor.placesSeen[group] = true
    if SC.Commands and type(SC.Commands.persist) == "function" then
        pcall(SC.Commands.persist, actor)
    end
    return true
end

local function placePulse(player, records, current)
    local utility = U()
    local square = utility.squareOf(player)
    local roomName = utility.roomName and utility.roomName(square) or nil
    local group = roomName and ROOM_GROUPS[string.lower(tostring(roomName))] or nil
    if group == nil then return false, "place_not_notable" end
    local building = buildingOf(square)
    local key = tostring(building or roomName) .. "|" .. group
    if party.placeKeys[key] then return false, "place_already_commented" end
    if current - party.lastPlaceAt < config("placeCommentPartyCooldownMs", 60000) then
        return false, "place_cooldown"
    end
    if not budgetAllows(current) then return false, "flavor_budget" end
    local radius = config("placeCommentRadius", 8)
    local lines = PLACE_LINES[group] or {}
    local best, bestCommands, bestTopic, bestScore
    for _, record in ipairs(records or {}) do
        local commands = available(record, player, current, radius)
        if commands and not placeSeen(record.actor, commands, group)
            and (building == nil or buildingOf(utility.squareOf(record.actor)) == building) then
            local profession = professionOf(commands)
            local matched = profession and type(lines.professions) == "table"
                and lines.professions[profession] ~= nil
            local score = (matched and 10 or 0) - utility.distance(record.actor, player) * 0.1
            if bestScore == nil or score > bestScore then
                best, bestCommands, bestScore = record.actor, commands, score
                bestTopic = "banter.place." .. group .. (matched and ("." .. profession) or "")
            end
        end
    end
    if best == nil then return false, "place_no_speaker" end
    if not speak(best, bestTopic, bestCommands) then return false, "place_speech_rejected" end
    if SC.Diary and type(SC.Diary.notePlace) == "function" then
        pcall(SC.Diary.notePlace, best, group, string.find(bestTopic, group .. ".", 1, true) ~= nil)
    end
    rememberSeenPlace(best, bestCommands, group)
    rememberPlace(key)
    party.lastPlaceAt = current
    party.lastFlavorAt = current
    return true, bestTopic
end

-- ---------------------------------------------------------------------------
-- Party pulse
-- ---------------------------------------------------------------------------

-- One party-level pulse from the runtime's background lane: track the idle
-- clock, then try a first-visit place remark, then an idle joke.
function Banter.update(player, records, current)
    if not enabled() then return false, "banter_disabled" end
    if player == nil or U().isDead(player) then return false, "banter_no_player" end
    current = tonumber(current) or U().nowMs()
    if type(records) ~= "table" then
        records = SC.Registry and type(SC.Registry.records) == "function"
            and SC.Registry.records() or {}
    end
    local exchanged, exchangeReason, exchangeBusy = exchangePulse(records, current)
    if exchanged or exchangeBusy then return exchanged, exchangeReason end
    local greeted, greetingReason = greetingPulse(player, records, current)
    if greeted then return true, greetingReason end
    local interiorSpoken, interiorReason = interiorPartyPulse(player, records, current)
    if interiorSpoken then return true, interiorReason end
    local idle, inVehicle = trackIdle(player, current)
    if SC.Tales and type(SC.Tales.update) == "function" then
        local ok, telling, taleReason = pcall(SC.Tales.update, player, records, current)
        if ok and telling then return true, taleReason end
    end
    local placed, placeReason = placePulse(player, records, current)
    if placed then return true, placeReason end
    local chatted, chatReason = campConversationPulse(player, records, current)
    if chatted then return true, chatReason end
    return jokePulse(player, records, current, idle, inVehicle)
end

function Banter.reset(actor)
    if actor ~= nil then
        actors[actor] = nil
        return true
    end
    party = freshParty()
    actors = setmetatable({}, { __mode = "k" })
    return true
end

-- Test seams.
function Banter._poolsForTests()
    return POOLS, PLACE_LINES, ROOM_GROUPS
end


function Banter._socialForTests()
    return greetingPulse, campConversationPulse, exchangePulse
end

function Banter._partyForTests()
    return party
end

return Banter
