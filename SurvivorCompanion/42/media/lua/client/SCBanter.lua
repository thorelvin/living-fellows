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
    ["banter.shelter.open"] = {
        common = {
            "%1, did you hear anything outside?",
            "This room is quiet enough to talk. How are you holding up, %1?",
            "%1, remind me what we're doing after we get home.",
            "You have been quiet, %1. Want some company?",
            "We have a minute before moving on. What is on your mind, %1?",
        },
        cautious = { "%1, keep your voice low. I think this place is clear." },
        caring = { "You look tired, %1. Talk to me." },
        practical = { "%1, take a breath. We can check the next room together." },
    },
    ["banter.shelter.reply"] = {
        common = {
            "Nothing outside yet. I'll keep listening, %1.",
            "I'm all right. It helps to hear another voice.",
            "After this? A locked door, a hot meal, and an hour asleep.",
            "Company sounds good. Just for a minute.",
            "I was thinking about the people we left behind. Let's keep moving soon.",
        },
        cautious = { "Quiet so far. I'd still watch the windows." },
        caring = { "I'm tired, but I'm glad you're here, %1." },
        practical = { "One room at a time. We'll manage." },
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
    ["banter.routine"] = {
        common = {
            "Keep an ear on the doors. I'll mind this side.",
            "Quiet places make me listen harder.",
            "Somebody used to have a normal day here.",
            "If you see trouble first, say it plain.",
            "We have time. Let's use it carefully.",
            "The road outside looks calm. I don't trust it yet.",
            "I'll keep looking. You keep watch.",
            "No need to rush into a bad surprise.",
            "If we split up, keep your voice low and close.",
            "Funny how a room can feel crowded with nobody in it.",
            "Remember, folks: idle hands get eaten.",
            "Another productive day in scenic Knox County.",
            "Nothing like routine to keep the screaming on the inside.",
            "Mind the mess. Civilization left in a hurry.",
            "Good news, no commute. Bad news, the reason why.",
            "Maybe a radio's still promising help. Bless its heart.",
            "If anybody asks, I'm on break. Have been since July.",
            "Funny thing, the end of the world. Still got chores.",
            "Keeping busy at the end of the world. Mama would be proud.",
            "Dry county jokes hit different when clean water's scarce.",
            "Folks round here used to wave at strangers. Now we count them.",
            "Tobacco farmers knew the secret: keep your hands busy.",
            "This used to count as a work party. Minus the potluck.",
            "Hard to picture a Derby with nobody in the stands.",
            "Kentucky weather never cared who was left to complain about it.",
            "I'd trade every dollar in this county for cold sweet tea.",
        },
        brave = { "I'm still here. Whatever comes through, we'll handle it.",
            "World ended and I'm still on shift. Figures.",
            "Keep it coming. I've had worse jobs." },
        cautious = { "I keep checking the exits. Habit now.",
            "Work quiet when we can. Noise draws them like hogs to a bucket.",
            "Every creak takes a year off my life." },
        caring = { "You holding up? You don't have to answer right away.",
            "Remember to drink some water when you can.",
            "Take a breath if you need one. I'll keep going." },
        practical = { "We should count what we carry before moving on.",
            "Busy hands, full shelves. That's the whole plan.",
            "We keep going, then we eat. That's the deal." },
        steady = { "Nothing moving nearby. Let's keep it that way.",
            "Quiet enough to hear myself think. Almost." },
        stressed = { "Keep talking. The quiet's got teeth today.",
            "I'm wound tight today. Work helps. A little." },
        low = { "Some days I forget why we bother. Then I keep working anyway.",
            "Used to think somebody would come for us. Now I just fix things." },
        hopeful = { "Give it a year, maybe we'll have the only porch light in Kentucky.",
            "Feels almost like an ordinary day. Don't tell anybody." },
    },
    -- Walking with the player. Followers have no owned task, so routine
    -- banter never picks them and the idle jokes wait for a long stop.
    ["banter.follow"] = {
        common = {
            "Right behind you.",
            "You lead. I'll listen behind us.",
            "Watch the corners. They don't announce themselves.",
            "I'm counting the turns, in case we need to come back fast.",
            "Every quiet street still makes me look twice.",
            "Mind the cars. Something always hides behind one.",
            "If we stop, I'll take the side you're not watching.",
            "I keep expecting to hear a bus.",
            "Knox County never looked this empty on a weekday.",
            "Walking together beats walking alone. Even now.",
            "Funny. I used to come this way for groceries.",
            "Keep going. I've got your back.",
            "Lovely day for a walk through the end of everything.",
            "Scenic route again? You spoil me.",
            "Welcome to Knox County. Enjoy your stay. It's mandatory.",
            "If a billboard still promises tomorrow, that's bold of it.",
            "If the army's holding the county line, they're doing it real quiet.",
            "Nobody's paying bills anymore. Silver lining, I reckon.",
            "Walking the county like a census taker. Head count's way down.",
            "We walk much farther, I'm calling it a pilgrimage.",
            "I miss the smell of cut hay more than I expected.",
            "If a horse looks out of a barn, I'm stopping to say hello.",
            "Brandenburg roads could lead you to a church or a liquor store.",
            "Ohio River's still out there, rolling along. Must be nice.",
            "A Kentucky mile always was longer than it looks.",
            "Roadside ditches never used to worry me. Funny how that changed.",
            "They call it bluegrass country. Nobody told the dead.",
            "I miss seeing people sit out on their porches.",
        },
        brave = { "Point the way. I'll handle whatever's on it.",
            "I'd rather be out front, but fine. Lead on.",
            "Pick a direction. I'll make it work.",
            "Keep moving. I'll cover our back." },
        cautious = { "Slow is fine. Slow is alive.",
            "I keep checking behind us. Don't mind me.",
            "Keep off open fields if we can. Nothing to hide behind there.",
            "Stay off rotten porches. Worse things wait behind the doors." },
        caring = { "Shout if you need a breather. I won't think less of you.",
            "Say if you need a breather. We can take one.",
            "Talk to me now and then. Helps me know you're all right." },
        practical = { "Let's not carry more than we can run with.",
            "Water towers and church steeples make decent landmarks.",
            "Every mile out is a mile back. Pack for both." },
        steady = { "Same road, same rules. Eyes open.",
            "Nothing behind us. I checked twice.",
            "Still with you. Long road ahead." },
        stressed = { "Let's keep moving. Standing still makes my skin crawl.",
            "Every shadow's got teeth today." },
        low = { "Another road, another day. Hard to tell them apart.",
            "Sometimes I wonder who'll walk these roads after us." },
        hopeful = { "Somewhere out there's a town with the lights on. I'd bet my boots.",
            "Keep this pace and we'll outlast the whole county." },
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
        steady = { "Another day nobody's going to write down.",
            "Nothing's on fire. Let's not tempt it." },
    },
    ["banter.idle.second"] = {
        common = {
            "Ten minutes. I've named every fly in this room.",
            "I'm starting to think you're a very lifelike statue.",
            "If we're waiting, I'm getting my reps in. In my head.",
            "Knox County's longest staring contest. You're winning.",
        },
        steady = { "Still waiting. Fine. Not good. Fine.",
            "Could be worse. I can't think how, but it could." },
    },
    ["banter.idle.vehicle"] = {
        common = {
            "Engine's not gonna fix itself. Neither is my mood.",
            "Are we parked, or are we thinking about being parked?",
            "Nice car. Nicer when it moves.",
            "I could walk faster than this. Sitting down.",
        },
        steady = { "Vehicle remains stationary. Strong performance so far.",
            "We're still parked. At least the scenery is dependable." },
    },
}

if not SC.IntrusiveLines and type(require) == "function" then
    pcall(require, "SCIntrusiveLines")
end
for topic, specification in pairs(SC.IntrusiveLines or {}) do
    POOLS[topic] = specification
end

-- Each table exchange keeps one subject for all three turns. The speaker's
-- voice selector still picks a line within that subject; independent topics
-- would make a reply about supper answer a question about the roof.
local TABLE_TALKS = {
    tea = {
        open = {
            "Milli's kettle is making its rounds. Who wants cold tea?",
            "I found one of Milli's teabags. She says it has one more cup in it.",
            "Milli says tea tastes better when nobody is shooting. Let's test that, %1.",
            "There's tea, if you don't mind it cold and a little suspicious.",
        },
        reply = {
            "Cold tea and company beat hot tea alone.",
            "I'll take a cup. Just keep Bandit out of the muffins.",
            "Pour me one. I'll pretend the stove still works.",
            "Only if Dumpling isn't sitting in the cup again.",
        },
        close = {
            "Put the kettle back by Milli. She'll want it tomorrow.",
            "That was almost an ordinary afternoon. I'll take it.",
            "Best cup since the power went. Don't tell Milli it was the only one.",
            "Rinse the cups. Milli counts them every night.",
        },
    },
    meal = {
        open = {
            "This table used to mean supper. What would you put on it tonight, %1?",
            "It's strange how a table makes a small meal feel less lonely.",
            "If we could cook one proper meal, what would you ask for, %1?",
            "Remember when somebody else worried about what was for dinner?",
            "These chairs make canned beans feel almost respectable.",
            "I keep imagining fresh bread on this table. That smell, you know?",
        },
        reply = {
            "Hot soup would do. Something with a spoon and no hurry.",
            "I'd take eggs and toast. Burn the toast if you like.",
            "Beans taste better when someone stays to eat with you.",
            "A tomato from the garden would make this feel like a feast.",
            "I'd settle for tea that stayed hot until the last sip.",
            "Bread, if we ever get the flour. I'd even wash the dishes.",
        },
        close = {
            "Then that's a plan. One decent meal, all of us at this table.",
            "I'll save you the good spoon if we ever find one.",
            "For now, pass the tin. Company helps.",
            "Funny how much a plate can make a place feel like home.",
            "We should eat together more often, even when the menu's grim.",
            "I'll remember that order if the world ever opens a diner again.",
        },
    },
    chores = {
        open = {
            "The work can wait five minutes. How are your hands holding up?",
            "I spent half the day fixing things that broke yesterday.",
            "If the roof starts leaking, do we have a better plan than a bucket?",
            "We have a list of jobs longer than this table, %1.",
            "Who decided a safe house would need this much sweeping?",
            "Every house has one loose board that waits until you're tired.",
        },
        reply = {
            "My hands are sore, but the wall's still standing.",
            "A bucket buys us time. Dry boards will take longer.",
            "We can do one job at a time. That's how we got this far.",
            "I'd trade a week's sweeping for one working mop.",
            "Tomorrow I'll check the hinges. They sound like a warning bell.",
            "The place has more faults than people. We'll catch up.",
        },
        close = {
            "All right. Finish the tea first, then we'll see what needs doing.",
            "That can be tomorrow's problem. Tonight the walls held.",
            "Put it on the list. I'll help when these legs remember their job.",
            "You're right. A house gets fixed one stubborn piece at a time.",
            "We'll leave the bucket out and call it engineering.",
            "Good. Nobody has to carry the whole place alone.",
        },
    },
    rain = {
        open = {
            "Rain on the roof sounds like gravel from this chair.",
            "Does the weather ever give us a day without an argument?",
            "I used to like a storm when I had a warm room to watch it from.",
            "The rain keeps tapping at the windows like it wants in.",
            "You can almost smell the wet fields through the walls.",
            "The rain makes every light in this room look warmer.",
        },
        reply = {
            "At least rain keeps the dust down on the road.",
            "If the shutters hold, I can almost sleep to it.",
            "Wet fields might give us something to grow next month.",
            "Storms used to mean a day indoors and a pot on the stove.",
            "I checked the window. No leak there yet.",
            "Cold rain's honest. It tells you what kind of day you're having.",
        },
        close = {
            "We'll listen from this side of the glass, then.",
            "Maybe the morning will smell clean, for once.",
            "If the roof lets go, wake me. Otherwise let it sing.",
            "A dry chair and someone to talk to. I'll take it.",
            "There's worse company than weather. Much worse.",
            "We'll put another log on before the cold gets ideas.",
        },
    },
    before = {
        open = {
            "What did your kitchen sound like before all this, %1?",
            "I keep trying to remember the last ordinary Sunday.",
            "There was a diner outside town. The coffee was terrible. I miss it.",
            "My family used to argue over who sat by the window.",
            "This table reminds me of one my grandmother kept under a yellow lamp.",
            "I used to complain about crowded dinners. Can you believe that?",
        },
        reply = {
            "Mine was loud. Cutlery, radio, somebody laughing too hard.",
            "Sunday meant dishes in the sink and nowhere urgent to be.",
            "Bad coffee sounds good now. I'd drink the whole pot.",
            "We argued about seats too. Nobody wanted the wobbly chair.",
            "I remember a lamp like that. Warm light on the tablecloth.",
            "Crowded meant there was always someone to pass the salt.",
        },
        close = {
            "Keep telling me those things. I don't want to forget the sound.",
            "The old days weren't perfect. They were ours.",
            "We'll make a new Sunday here when we can.",
            "Maybe that's why I like this table. It gives the memories a place.",
            "I can almost hear that kitchen when you talk about it.",
            "Thanks. For a minute, I remembered something besides July.",
        },
    },
    tomorrow = {
        open = {
            "If the road's clear tomorrow, what do we need most?",
            "We should decide which chore gets daylight first.",
            "Before the next supply run, we should agree on what matters most.",
            "If there's trouble outside, I'd rather check it in daylight.",
            "Let's talk tomorrow before everyone scatters, %1.",
            "One good tool always seems to be needed in two places.",
        },
        reply = {
            "Water first. Everything else waits if the cans are empty.",
            "I'll check the fence before anyone heads out.",
            "A short run for food beats a long one with tired legs.",
            "Those tracks can wait until we can see both ends of the road.",
            "Leave the tools where everybody can find them. We'll take turns.",
            "Let's sleep on it and decide with a little daylight.",
        },
        close = {
            "Fair. We'll make the call after breakfast.",
            "I'll tell the others when they come in.",
            "No heroic detours, then. We get what we need and come home.",
            "That sounds like a plan people might survive.",
            "We'll leave a note by the door so nobody misses it.",
            "Good. It's easier to face tomorrow when it has a shape.",
        },
    },
    little_things = {
        open = {
            "Someone straightened these chairs. I noticed.",
            "There was a bird on the sill this morning. Just watching us.",
            "I found a blue cup in the cupboard. Kept it for no reason.",
            "The floor creaks in the same place every time. It's becoming familiar.",
            "I heard somebody humming while they worked today.",
            "This room still smells a little like coffee after the fire goes out.",
        },
        reply = {
            "A chair in the right place makes it easier to sit a while.",
            "Birds don't know the world ended. I envy them for that.",
            "Keep the cup. We're allowed to like things.",
            "Familiar sounds are better than surprising ones.",
            "I heard it too. I almost joined in.",
            "Coffee or smoke, I'll take a warm room either way.",
        },
        close = {
            "We should hold on to the little things. They add up.",
            "Maybe that's what makes this place ours.",
            "You can have the blue cup next time.",
            "If I start humming, you have permission to complain.",
            "I needed that thought more than I knew.",
            "All right. One quiet minute, then back to the world.",
        },
    },
}
local TABLE_THEME_KEYS = { "meal", "chores", "rain", "before", "tomorrow",
    "little_things" }
local function tableThemeAvailable(theme)
    if theme ~= "rain" then return true end
    if type(getClimateManager) ~= "function" then return false end
    local ok, manager = pcall(getClimateManager)
    return ok and manager ~= nil
        and select(1, U().call(manager, "isRaining")) == true
end
for theme, stages in pairs(TABLE_TALKS) do
    for stage, lines in pairs(stages) do
        POOLS["banter.table." .. theme .. "." .. stage] = { common = lines }
    end
end

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
    hunting = "hunting",
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
    hunting = {
        common = {
            "Field guides. Take one before we need it.",
            "The racks are empty. Somebody planned a long season.",
            "A store for hunting things that hunt back now.",
            "I used to come here for boots. I'd still take a good pair.",
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

-- Hopeful companions sometimes read the dead county's institutional optimism
-- back to the room. These are place-specific so the register stays occasional
-- without becoming the same two poster jokes in every building.
local PLACE_HOPEFUL = {
    police = { "Sign says remain calm and await instructions. I'm doing my part.",
        "'Your County Cares.' Past tense, I think." },
    prison = { "Emergency shelter: secure doors, controlled entry. They certainly managed that.",
        "The notice promises orderly release. We may be a little outside office hours." },
    church = { "Poster calls this a community refuge. The community seems delayed.",
        "'Shelter, comfort, fellowship.' Two out of three would be excellent." },
    bar = { "County morale station. Refreshments subject to availability.",
        "The sign says drink responsibly. At last, an instruction still in force." },
    liquor = { "Emergency morale supplies. Somebody planned ahead after all.",
        "'Please ration purchases.' The county's honor system has seen better days." },
    whiskey = { "Strategic Kentucky reserve. National morale is apparently in barrels.",
        "Tour notice says every barrel is part of our future. Optimistic, that." },
    brewery = { "Poster says quality brings people together. It neglected to specify alive people.",
        "'Serving the community since 1948.' Service is currently self-directed." },
    school = { "Civil Defense assembly point. Form one orderly line, children.",
        "Poster says preparedness starts in the classroom. Class dismissed." },
    library = { "Public information center. Further updates are in the fiction aisle.",
        "Says here knowledge is protection. Good. We can carry several books." },
    gunstore = { "Personal defense guidance: stay calm, check your target, conserve ammunition.",
        "The safety poster says every weapon has an owner. Applications are open." },
    pharmacy = { "County health notice: keep three days of medicine. Optimistic, that.",
        "'Ask your pharmacist.' I'd love to. Office hours appear irregular." },
    hospital = { "Sign says report symptoms promptly. We are a few weeks behind schedule.",
        "Poster says the situation is under control. It's dated July." },
    morgue = { "Public Health says every case will be recorded. They ran out of tags first.",
        "The form says final disposition pending. We can help with that part." },
    dentist = { "Emergency notice says routine appointments may be delayed. Fair assessment.",
        "Poster says a healthy smile builds confidence. The model has all his teeth." },
    spiffos = { "Approved family feeding station. Mascot remains calm and operational.",
        "Poster promises a meal and a smile. We may have to supply both." },
    jays = { "Community hot-meal site. Hot is aspirational, but meal sounds good.",
        "The sign says every bucket brings folks together. Bring a can opener." },
    grocery = { "Leaflet here: three days of water per person. Optimistic, that.",
        "'No need to panic-buy.' Somebody printed that with a straight face." },
    gas = { "Evacuation route fuel point. Please have exact change and a working nation.",
        "Sign says check fuel before travel. Clear, practical, several weeks late." },
    garage = { "Emergency motor pool instructions. Step one: locate an authorized mechanic.",
        "Poster says preventive maintenance keeps Kentucky moving. We'll do our part." },
    firehouse = { "County Emergency Services: always ready. They were. That was the trouble.",
        "The board says help is one call away. Telephone service not included." },
    army = { "Notice says the situation is contained. Someone laminated this.",
        "'Cooperate with military authorities.' Awaiting authorities." },
    theatre = { "Civil Defense information film at seven. Feature presentation postponed.",
        "The screen promises important public guidance. Concessions sold separately." },
    bowling = { "County notice says recreation maintains public morale. Roll carefully.",
        "'League play builds community resilience.' Finally, a plan with lanes." },
    stripclub = { "Approved recreation venue. Official guidance remains tactfully vague.",
        "Poster says support local workers. The county really did think of everything." },
    lab = { "Biohazard notice says trained personnel only. Good news: nobody is checking.",
        "The placard says the situation is under control. Strong wording for this room." },
    motel = { "Temporary evacuation lodging. Checkout time has been generously extended.",
        "Sign says clean rooms and friendly service. One of those may still be true." },
    laundry = { "Sanitation protects the community. At last, advice we can actually use.",
        "Poster says cleanliness is everyone's duty. Quarters are everyone's problem." },
    gym = { "Prepared citizens stay fit. The county would be proud of all this running.",
        "Civil Defense fitness standard: remain mobile. We are exceeding expectations." },
    music = { "Morale broadcast equipment. Stay tuned for further updates. I'm all ears.",
        "Poster says music keeps communities strong. Power supply not pictured." },
    books = { "Official preparedness guides, revised annually. July interrupted revisions.",
        "Says here informed citizens make calm citizens. Let's take two." },
    zippee = { "Designated emergency supply point, open twenty-four hours. Technically true.",
        "The sign promises fast service in any crisis. Self-service counts." },
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
        specification.hopeful = PLACE_HOPEFUL[group]
        SC.Dialogue.register("banter.place." .. group, specification)
        for profession, lines in pairs(entry.professions or {}) do
            SC.Dialogue.register("banter.place." .. group .. "." .. profession, {
                common = lines, hopeful = PLACE_HOPEFUL[group],
            })
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
        lastRoutineAt = -math.huge,
        lastFollowAt = -math.huge,
        lastPassengerAt = -math.huge,
        lastIntrusiveAt = -math.huge,
        intrusiveRecent = {},
        intrusiveRecentSet = {},
        lastMovedAt = -math.huge,
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
    local ok, spoken, line, detail = pcall(SC.Dialogue.say,
        actor, topic, nil, arguments, settings)
    return ok and spoken == true, line, detail
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

-- Speech-only observations can coexist with an owned action. Exchanges that
-- face or move actors still require an idle speaker.
local function available(record, player, current, radius, speechOnly)
    local actor = type(record) == "table" and record.actor or nil
    local utility = U()
    if actor == nil or not utility.isValidActor(actor) or utility.isDead(actor) then return nil end
    local commands = commandState(actor)
    if commands.recruited ~= true then return nil end
    if not calm(recordSnapshot(record)) then return nil end
    if not utility.sameFloor(actor, player) or utility.distance(actor, player) > radius then
        return nil
    end
    if not speechOnly and SC.ActionSupervisor
        and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) ~= nil then return nil end
    local spokenAt = lastSpokenAt(actor)
    if spokenAt and current - spokenAt < config("banterSpeakerQuietMs", 15000) then return nil end
    return commands
end

local budgetAllows
local intrusiveRemember

local function callName(speaker, listener, context)
    if SC.Names and type(SC.Names.callName) == "function" then
        local ok, name = pcall(SC.Names.callName, speaker, listener, context)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local name = tostring(U().nameOf(listener) or "")
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

local tableServesPair

local function beginExchange(first, second, openTopic, replyTopic,
        firstCommands, secondCommands, current, kind, faceToFace)
    local salt = kind .. ":open:" .. pairKey(first, second) .. ":" .. tostring(current)
    if not speak(first, openTopic, firstCommands,
        { callName(first, second, { salt = salt }) }, {
        salt = salt,
    }) then return false, "conversation_speech_rejected" end
    if faceToFace ~= false then
        faceConversation(first, second, kind,
            kind == "meeting" and "wave" or "yes", "yes")
    end
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
        or U().isDead(exchange.second)
        or not U().sameFloor(exchange.first, exchange.second)
        or U().distance(exchange.first, exchange.second)
            > config("campConversationDistance", 8) then
        party.exchange = nil
        return false, "conversation_interrupted", false
    end
    if exchange.kind == "table" and not tableServesPair(exchange.first,
        exchange.second, exchange.tableObject) then
        party.exchange = nil
        return false, "table_conversation_interrupted", false
    end
    if exchange.kind == "intrusive" then
        local replyCommands = freeSurvivor(secondRecord, current)
        if not replyCommands or replyCommands.recruited ~= true
            or select(1, U().call(exchange.second, "isMoving")) == true then
            party.exchange = nil
            return false, "intrusive_reply_busy", false
        end
    end
    if current < (exchange.nextAt or 0) then return false, "conversation_waiting", true end
    local closing = exchange.stage == "close"
    local speaker = closing and exchange.first or exchange.second
    local topic = closing and exchange.closeTopic or exchange.replyTopic
    local commands = closing and exchange.firstCommands or exchange.secondCommands
    local other = closing and exchange.second or exchange.first
    local salt = exchange.kind .. ":" .. (closing and "close" or "reply") .. ":"
        .. pairKey(exchange.first, exchange.second) .. ":" .. tostring(current)
    local spoken, _, detail = speak(speaker, topic, commands,
        { callName(speaker, other, { salt = salt }) }, {
            salt = salt,
            excludedLines = exchange.kind == "intrusive"
                and party.intrusiveRecentSet or nil,
            recentLimit = exchange.kind == "intrusive"
                and config("intrusiveRecentLimit", 60) or nil,
        })
    if not spoken then
        party.exchange = nil
        return false, "conversation_reply_rejected", false
    end
    party.lastFlavorAt = current
    if exchange.kind == "intrusive" then
        intrusiveRemember(type(detail) == "table" and detail.lineKey)
    end
    if not closing and exchange.closeTopic then
        exchange.stage = "close"
        exchange.nextAt = current + config("companionConversationReplyMs", 2800)
        exchange.expiresAt = current + 12000
        return true, topic, true
    end
    party.exchange = nil
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
            if SC.NicknameLife and type(SC.NicknameLife.maybeCoin) == "function"
                and U().sameFloor(first, player)
                and U().distance(first, player) <= radius then
                local salt = "player:coin:" .. tostring(U().idOf(first))
                    .. ":" .. tostring(current)
                local ok, coined = pcall(SC.NicknameLife.maybeCoin, first, player, salt)
                if ok and coined == true then
                    party.lastFlavorAt = current
                    return true, "nickname_coin_player"
                end
            end
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

-- The camp boundary plus the work zones in its reach band (logging, farm,
-- burial ground, pyre). Residents and followers spend camp time there too,
-- and the boundary alone left the logging area silent.
local function atCamp(actor)
    local life = SC.BaseLife
    if not life or type(life.isInside) ~= "function" then return false end
    if life.isInside(actor) == true then return true end
    local reach = type(life.REACH_ZONE_KINDS) == "table" and life.REACH_ZONE_KINDS or {}
    for kind in pairs(reach) do
        if life.isInside(actor, kind) == true then return true end
    end
    return false
end

local function shelteredTogether(first, second)
    local firstSquare = U().squareOf(first)
    local secondSquare = U().squareOf(second)
    local firstRoom = firstSquare and select(1, U().call(firstSquare, "getRoom"))
    local secondRoom = secondSquare and select(1, U().call(secondSquare, "getRoom"))
    if firstRoom == nil or secondRoom == nil then return false end
    local firstBuilding = select(1, U().call(firstRoom, "getBuilding"))
    local secondBuilding = select(1, U().call(secondRoom, "getBuilding"))
    return firstBuilding ~= nil and firstBuilding == secondBuilding
end

local quietAction = {
    sit = true, rest_bed = true, rest_floor = true,
    read = true, write_diary = true,
    window_watch = true, tv_watch = true, gear_check = true, radio_check = true,
    tidy_camp = true, weather_recovery = true, clean_base = true,
}

local function isTableFurniture(object)
    local sprite = select(1, U().call(object, "getSprite"))
    local properties = sprite and select(1, U().call(sprite, "getProperties"))
    return properties ~= nil
        and select(1, U().call(properties, "has", "IsTable")) == true
end

local function seatedForConversation(actor)
    if select(1, U().call(actor, "isSittingOnFurniture")) ~= true
        or select(1, U().call(actor, "isAsleep")) == true
        or select(1, U().call(actor, "isMoving")) == true then return false end
    local supervisor = SC.ActionSupervisor
    local token = supervisor and type(supervisor.current) == "function"
        and supervisor.current(actor) or nil
    if token and (token.owner ~= "downtime" or token.action ~= "sit") then
        return false
    end
    return not (SC.Positioning
        and type(SC.Positioning.activeConversation) == "function"
        and SC.Positioning.activeConversation(actor) ~= nil)
end

tableServesPair = function(first, second, object)
    if object == nil or not seatedForConversation(first)
        or not seatedForConversation(second) then return false end
    local firstSquare, secondSquare = U().squareOf(first), U().squareOf(second)
    local tableSquare = U().squareOf(object)
    local room = firstSquare and select(1, U().call(firstSquare, "getRoom"))
    if room == nil or not secondSquare or not tableSquare
        or select(1, U().call(secondSquare, "getRoom")) ~= room
        or select(1, U().call(tableSquare, "getRoom")) ~= room
        or not isTableFurniture(object)
        or (U().distance(first, tableSquare) or math.huge) > 2.25
        or (U().distance(second, tableSquare) or math.huge) > 2.25 then
        return false
    end
    local stillThere = false
    U().squareObjects(tableSquare, function(candidate)
        if candidate == object then stillThere = true return false end
        return true
    end, 48)
    return stillThere
end

local function sharedTable(first, second)
    if not seatedForConversation(first) or not seatedForConversation(second)
        then return nil end
    local ax, ay, az = U().position(first)
    if ax == nil then return nil end
    for dx = -2, 2 do
        for dy = -2, 2 do
            local square = U().gridSquare(ax + dx, ay + dy, az)
            local found
            U().squareObjects(square, function(object)
                if tableServesPair(first, second, object) then
                    found = object
                    return false
                end
                return true
            end, 24)
            if found then return found end
        end
    end
    return nil
end

local function availableForQuietTalk(record, player, current, radius)
    local commands = available(record, player, current, radius, true)
    if not commands then return nil end
    local supervisor = SC.ActionSupervisor
    local token = supervisor and type(supervisor.current) == "function"
        and supervisor.current(record.actor) or nil
    if token ~= nil and (token.owner ~= "downtime"
        or quietAction[token.action] ~= true) then return nil end
    return commands, token == nil
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
        local commands, freeToFace = availableForQuietTalk(record, player, current,
            config("meetingGreetingPlayerDistance", 14))
        local moving, movingOk = record.actor and U().call(record.actor, "isMoving")
        if commands and (atCamp(record.actor)
            or select(1, U().call(U().squareOf(record.actor), "getRoom")) ~= nil)
            and not (movingOk and moving == true)
            and current - (actorState(record.actor).lastCampTalkAt or -math.huge)
                >= actorCooldown then
            candidates[#candidates + 1] = {
                record = record, commands = commands, freeToFace = freeToFace,
            }
        end
    end
    for firstIndex = 1, #candidates do
        for secondIndex = firstIndex + 1, #candidates do
            local first, second = candidates[firstIndex], candidates[secondIndex]
            local firstActor, secondActor = first.record.actor, second.record.actor
            local key = pairKey(firstActor, secondActor)
            local prior = tonumber(party.campPairs[key]) or -math.huge
            local campPair = atCamp(firstActor) and atCamp(secondActor)
            if (campPair or shelteredTogether(firstActor, secondActor))
                and U().sameFloor(firstActor, secondActor)
                and U().distance(firstActor, secondActor) <= radius
                and U().canSee(firstActor, secondActor)
                and current - prior >= config("campConversationPairCooldownMs", 600000) then
                local tableObject = sharedTable(firstActor, secondActor)
                local openTopic = campPair and "banter.camp.open"
                    or "banter.shelter.open"
                local replyTopic = campPair and "banter.camp.reply"
                    or "banter.shelter.reply"
                -- A carried library book gives a quiet pair something
                -- concrete to discuss. Keep ordinary camp talk in rotation.
                local bookConversation = SC.Downtime
                    and type(SC.Downtime.hasBookToDiscuss) == "function"
                    and (SC.Downtime.hasBookToDiscuss(firstActor)
                        or SC.Downtime.hasBookToDiscuss(secondActor))
                    and U().stableHash(key .. ":books:" .. tostring(math.floor(current / 60000)))
                        % 3 == 0
                if bookConversation then
                    openTopic, replyTopic = "banter.books.open", "banter.books.reply"
                end
                local closeTopic, conversationKind
                if tableObject then
                    local salt = math.abs(tonumber(U().stableHash(key .. ":table:"
                        .. tostring(math.floor(current / 60000)))) or 0)
                    local firstGroup = SC.Oddballs and SC.Oddballs.groupForActor
                        and SC.Oddballs.groupForActor(firstActor)
                    local secondGroup = SC.Oddballs and SC.Oddballs.groupForActor
                        and SC.Oddballs.groupForActor(secondActor)
                    local milliAtTable = firstGroup and firstGroup.oddball
                        and firstGroup.oddball.id == "milli_tea_and_trouble"
                        or secondGroup and secondGroup.oddball
                            and secondGroup.oddball.id == "milli_tea_and_trouble"
                    local theme
                    if milliAtTable and salt % 3 == 0 then
                        theme = "tea"
                    else
                        local index = salt % #TABLE_THEME_KEYS + 1
                        if not tableThemeAvailable(TABLE_THEME_KEYS[index]) then
                            index = index % #TABLE_THEME_KEYS + 1
                        end
                        theme = TABLE_THEME_KEYS[index]
                    end
                    local prefix = "banter.table." .. theme
                    openTopic, replyTopic, closeTopic = prefix .. ".open",
                        prefix .. ".reply", prefix .. ".close"
                    conversationKind = "table"
                else
                    conversationKind = campPair and "camp" or "shelter"
                end
                if SC.NicknameLife and type(SC.NicknameLife.maybeCoin) == "function" then
                    local coinSalt = conversationKind .. ":coin:" .. key
                        .. ":" .. tostring(current)
                    local ok, coined = pcall(SC.NicknameLife.maybeCoin,
                        firstActor, secondActor, coinSalt)
                    if ok and coined == true then
                        actorState(firstActor).lastCampTalkAt = current
                        actorState(secondActor).lastCampTalkAt = current
                        rememberPair("campPairs", "campPairCount", key, current, 128)
                        party.lastCampConversationAt = current
                        party.lastFlavorAt = current
                        return true, "nickname_coin"
                    end
                end
                local spoken, topic = beginExchange(firstActor, secondActor,
                    openTopic, replyTopic,
                    first.commands, second.commands, current,
                    conversationKind,
                    not tableObject and first.freeToFace and second.freeToFace)
                if spoken then
                    if tableObject then
                        party.exchange.tableObject = tableObject
                        party.exchange.closeTopic = closeTopic
                        party.exchange.firstCommands = first.commands
                        party.exchange.expiresAt = current + 18000
                        if SC.Gestures
                            and type(SC.Gestures.seatedConversation) == "function"
                            and roll(config("tableConversationGestureChancePercent", 40),
                                firstActor, current) then
                            local gesturer = U().stableHash(key .. ":gesture:"
                                .. tostring(current)) % 2 == 0
                                and firstActor or secondActor
                            pcall(SC.Gestures.seatedConversation, gesturer, current)
                        end
                    end
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

local function intrusiveClock()
    if type(getGameTime) ~= "function" then return nil, nil end
    local ok, clock = pcall(getGameTime)
    if not ok or clock == nil then return nil, nil end
    local age = tonumber((U().call(clock, "getWorldAgeHours")))
    local hour = tonumber((U().call(clock, "getHour")))
    return age, hour
end

local function intrusiveRoll(percent, actor, current, tag)
    percent = tonumber(percent) or 0
    if percent <= 0 then return false end
    if percent >= 100 then return true end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, 100)
        if ok and tonumber(value) then return tonumber(value) < percent end
    end
    local seed = tostring(U().idOf(actor)) .. ":" .. tostring(tag) .. ":"
        .. tostring(math.floor(current / 1000))
    return math.abs(tonumber(U().stableHash(seed)) or 0) % 100 < percent
end

intrusiveRemember = function(key)
    if type(key) ~= "string" or key == "" then return end
    local recent, lookup = party.intrusiveRecent, party.intrusiveRecentSet
    if lookup[key] then return end
    recent[#recent + 1], lookup[key] = key, true
    local limit = math.max(0, math.floor(config("intrusiveRecentLimit", 60)))
    while #recent > limit do lookup[table.remove(recent, 1)] = nil end
end

function Banter.noteKill(actor, current)
    if actor == nil then return false end
    actorState(actor).lastKillAt = tonumber(current) or U().nowMs()
    return true
end

local function intrusiveSafe(actor, records, current)
    if U().config("intrusiveThoughtsEnabled") == false then return false end
    if current - party.lastIntrusiveAt < config("intrusivePartyCooldownMs", 2700000)
        or current - party.lastRefusalAt < config("interiorRefusalPriorityMs", 5000)
        or party.exchange ~= nil or not budgetAllows(current) then return false end
    if SC.Tales and type(SC.Tales.isTelling) == "function"
        and SC.Tales.isTelling() == true then return false end
    if SC.Positioning and type(SC.Positioning.activeConversation) == "function"
        and SC.Positioning.activeConversation(actor) ~= nil then return false end
    local age = intrusiveClock()
    local own = actorState(actor)
    if age and own.lastIntrusiveHour
        and age - own.lastIntrusiveHour
            < config("intrusiveActorCooldownGameHours", 24) then return false end
    for _, record in ipairs(records or {}) do
        if record.actor and U().sameFloor(actor, record.actor)
            and U().distance(actor, record.actor) <= config("intrusiveReplyDistance", 6)
            and (not calm(recordSnapshot(record))
                or (SC.Positioning
                    and type(SC.Positioning.activeConversation) == "function"
                    and SC.Positioning.activeConversation(record.actor) ~= nil))
            then return false end
    end
    return true, age
end

local function intrusiveRoomGroup(actor)
    local square = U().squareOf(actor)
    local name = square and U().roomName and U().roomName(square) or nil
    local group = name and ROOM_GROUPS[string.lower(tostring(name))] or nil
    if not group or not POOLS["banter.intrusive.place." .. group] then return nil end
    local building = square and select(1, U().call(square, "getBuilding"))
    if party.placeKeys[tostring(building or name) .. "|" .. group] then return group end
    return nil
end

local function intrusiveHiddenBite(actor)
    local crisis = SC.InfectionCrisis
    if not crisis or type(crisis.peekForSubject) ~= "function" then return false end
    local ok, state = pcall(crisis.peekForSubject, tostring(U().idOf(actor)))
    return ok and type(state) == "table" and state.strategy == "conceal"
        and state.confessed ~= true and state.othersConfirmed ~= true
end

local function intrusiveGrieving(actor)
    if not SC.Community or type(SC.Community.activeGrief) ~= "function" then
        return false
    end
    local ok, grief = pcall(SC.Community.activeGrief, actor)
    return ok and type(grief) == "table"
        and (tonumber(grief.currentIntensity) or 0) > 0
end

local function intrusiveVehicle(actor)
    local vehicle = select(1, U().call(actor, "getVehicle"))
    if not vehicle then return nil end
    local driver = select(1, U().call(vehicle, "getDriver"))
    local speed = tonumber((U().call(vehicle, "getCurrentSpeedKmHour"))) or 0
    return driver ~= actor and math.abs(speed) > 1 and vehicle or nil
end

local function intrusiveNightWatch(actor, current)
    if not SC.BaseLife or type(SC.BaseLife.guardStatus) ~= "function"
        or not atCamp(actor) then return false end
    local ok, guarding = pcall(SC.BaseLife.guardStatus,
        tostring(U().idOf(actor)), current)
    return ok and guarding == true
end

local function intrusiveEating(actor, token)
    if token and (token.action == "eat_food" or token.action == "eat") then
        return true
    end
    if SC.NativeActions and type(SC.NativeActions.needsStatus) == "function" then
        local ok, active, kind = pcall(SC.NativeActions.needsStatus, actor)
        return ok and active == true and (kind == "eat" or kind == "eat_food")
    end
    return false
end

local PRIVATE_INTRUSIVE = {
    ["banter.intrusive.hidden_bite"] = true,
    ["banter.intrusive.grief"] = true,
    ["banter.intrusive.after_kill"] = true,
}

local function intrusiveReply(actor, records, current)
    if not intrusiveRoll(config("intrusiveReplyChancePercent", 35),
        actor, current, "reply") then return end
    local best, bestCommands, bestDistance
    for _, record in ipairs(records or {}) do
        local other = record.actor
        local commands = other ~= actor and freeSurvivor(record, current) or nil
        if commands and commands.recruited == true
            and U().sameFloor(actor, other)
            and select(1, U().call(other, "isMoving")) ~= true then
            local distance = U().distance(actor, other)
            if distance <= config("intrusiveReplyDistance", 6)
                and (bestDistance == nil or distance < bestDistance) then
                best, bestCommands, bestDistance = other, commands, distance
            end
        end
    end
    if not best then return end
    party.exchange = {
        first = actor, second = best, replyTopic = "banter.intrusive.reply",
        secondCommands = bestCommands,
        nextAt = current + config("companionConversationReplyMs", 2800),
        expiresAt = current + config("companionConversationTimeoutMs", 9000),
        kind = "intrusive",
    }
end

local function intrusivePulse(actor, commands, records, current, kind)
    local safe, age = intrusiveSafe(actor, records, current)
    if not safe then return false end
    local own = actorState(actor)
    local recentKill = own.lastKillAt
        and current - own.lastKillAt <= config("intrusiveEventWindowMs", 120000)
    local chance = recentKill
        and config("intrusiveAfterKillChancePercent", 12)
        or config("intrusiveChancePercent", 3)
    if not intrusiveRoll(chance, actor, current, "entry") then return false end
    local _, hour = intrusiveClock()
    local night = hour and (hour >= 21 or hour < 5)
    local square = U().squareOf(actor)
    local room = square and select(1, U().call(square, "getRoom"))
    local outdoors = square and room == nil
    local token = SC.ActionSupervisor and type(SC.ActionSupervisor.current) == "function"
        and SC.ActionSupervisor.current(actor) or nil
    local candidates = {}
    local function offer(suffix, eligible, share)
        if eligible and intrusiveRoll(share, actor, current, suffix) then
            candidates[#candidates + 1] = "banter.intrusive." .. suffix
        end
    end
    offer("hidden_bite", intrusiveHiddenBite(actor), 40)
    offer("grief", intrusiveGrieving(actor), 50)
    offer("after_kill", recentKill, 60)
    offer("passenger", kind == "passenger" and intrusiveVehicle(actor) ~= nil, 100)
    local _, _, z = U().position(actor)
    offer("height", z and (z >= 2 or (outdoors and z >= 1)), 50)
    offer("night_watch", night and intrusiveNightWatch(actor, current), 50)
    offer("eating", intrusiveEating(actor, token), 40)
    local group = intrusiveRoomGroup(actor)
    offer("place." .. tostring(group), group ~= nil, 40)
    offer("night", night, 35)
    local raining = false
    if outdoors and type(getClimateManager) == "function" then
        local ok, climate = pcall(getClimateManager)
        raining = ok and climate ~= nil
            and select(1, U().call(climate, "isRaining")) == true
    end
    offer("rain", raining, 35)
    offer("seated", select(1, U().call(actor, "isSittingOnFurniture")) == true, 30)
    local stress, morale = tonumber(commands.stress) or 0,
        tonumber(commands.morale) or 55
    offer("dark", true, (stress >= 65 or morale <= 28)
        and config("intrusiveDarkPercent", 35)
        or config("intrusiveDarkBasePercent", 10))
    candidates[#candidates + 1] = kind == "camp"
        and "banter.intrusive.camp" or "banter.intrusive.travel"
    for _, topic in ipairs(candidates) do
        local spoken, _, detail = speak(actor, topic, commands, nil, {
            salt = tostring(current), excludedLines = party.intrusiveRecentSet,
            recentLimit = config("intrusiveRecentLimit", 60),
        })
        if spoken then
            intrusiveRemember(type(detail) == "table" and detail.lineKey)
            party.lastIntrusiveAt = current
            party.lastFlavorAt = current
            own.lastIntrusiveHour = age
            if not PRIVATE_INTRUSIVE[topic] then intrusiveReply(actor, records, current) end
            return true, topic
        end
    end
    return false
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
    local salt = pairKey(actor, blocker) .. ":" .. tostring(current)
    local spoken = speak(actor, "banter.crowd.yield", commandState(actor),
        { callName(actor, blocker, { salt = salt, urgent = true }) }, {
            salt = salt,
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
    local stepped = idle ~= nil and (math.floor(z or 0) ~= math.floor(idle.z or 0)
        or (x - idle.x) * (x - idle.x) + (y - idle.y) * (y - idle.y) > 0.09)
    -- First sight of the player is not a step; follow chatter needs a real one.
    if stepped then party.lastMovedAt = current end
    if idle == nil or stepped or driving or playerBusy(player) then
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
        local commands = available(record, player, current, radius, true)
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

-- Ordinary work and downtime used to silence the whole party because their
-- supervisor tokens never released long enough for idle banter. This is only
-- overhead speech: it never touches that activity, facing, path or posture.
local function routinePulse(player, records, current)
    if current - party.lastRoutineAt
        < config("routineBanterIntervalMs", 90000) then
        return false, "routine_cooldown"
    end
    if not budgetAllows(current) then return false, "flavor_budget" end
    local supervisor = SC.ActionSupervisor
    if not supervisor or type(supervisor.current) ~= "function" then
        return false, "routine_owner_unavailable"
    end
    local best, bestCommands, oldest
    for _, record in ipairs(records or {}) do
        local actor = record.actor
        local commands = available(record, player, current,
            config("ambientDialogueDistance", 10), true)
        if commands and supervisor.current(actor) ~= nil then
            local prior = actorState(actor).lastRoutineAt or -math.huge
            if best == nil or prior < oldest then
                best, bestCommands, oldest = actor, commands, prior
            end
        end
    end
    if best == nil then return false, "routine_no_speaker" end
    local intrusive, topic = intrusivePulse(best, bestCommands, records, current, "camp")
    if not intrusive and not speak(best, "banter.routine", bestCommands) then
        return false, "routine_speech_rejected"
    end
    party.lastRoutineAt = current
    party.lastFlavorAt = current
    actorState(best).lastRoutineAt = current
    return true, intrusive and topic or "banter.routine"
end

-- A follower walking with the player has no owned task, so routine banter
-- skips it, and the idle jokes wait for a three-minute stop. Without this the
-- party said nothing at all on the move. Overhead speech only: it never
-- touches the formation, route or posture.
local function followPulse(player, records, current, inVehicle)
    if inVehicle then return false, "follow_in_vehicle" end
    if current - party.lastMovedAt >= config("followBanterSettledMs", 30000) then
        return false, "follow_leader_settled"
    end
    if current - party.lastFollowAt < config("followBanterIntervalMs", 120000) then
        return false, "follow_cooldown"
    end
    if not budgetAllows(current) then return false, "flavor_budget" end
    local supervisor = SC.ActionSupervisor
    local best, bestCommands, oldest
    for _, record in ipairs(records or {}) do
        local actor = record.actor
        local commands = available(record, player, current,
            config("ambientDialogueDistance", 10), true)
        if commands and commands.order == "follow"
            and not (supervisor and type(supervisor.current) == "function"
                and supervisor.current(actor) ~= nil) then
            local prior = actorState(actor).lastFollowAt or -math.huge
            if best == nil or prior < oldest then
                best, bestCommands, oldest = actor, commands, prior
            end
        end
    end
    if best == nil then return false, "follow_no_speaker" end
    local intrusive, topic = intrusivePulse(best, bestCommands, records, current, "travel")
    if not intrusive and not speak(best, "banter.follow", bestCommands) then
        return false, "follow_speech_rejected"
    end
    party.lastFollowAt = current
    party.lastFlavorAt = current
    actorState(best).lastFollowAt = current
    return true, intrusive and topic or "banter.follow"
end

local function passengerPulse(player, records, current)
    if current - party.lastPassengerAt < config("followBanterIntervalMs", 120000)
        then return false end
    local vehicle, moving = playerVehicle(player)
    if not moving or not budgetAllows(current) then return false end
    for _, record in ipairs(records or {}) do
        local actor = record.actor
        local commands = available(record, player, current,
            config("ambientDialogueDistance", 10), true)
        if commands and select(1, U().call(actor, "getVehicle")) == vehicle
            and intrusiveVehicle(actor) == vehicle then
            party.lastPassengerAt = current
            return intrusivePulse(actor, commands, records, current, "passenger")
        end
    end
    return false
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
    if SC.NicknameLife and type(SC.NicknameLife.pulse) == "function" then
        local spoken, reason = SC.NicknameLife.pulse(current)
        if spoken then return true, reason end
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
    local passengerSpoken, passengerTopic = passengerPulse(player, records, current)
    if passengerSpoken then return true, passengerTopic end
    local chatted, chatReason = campConversationPulse(player, records, current)
    if chatted then return true, chatReason end
    local joked, jokeReason = jokePulse(player, records, current, idle, inVehicle)
    if joked then return true, jokeReason end
    local remarked, routineReason = routinePulse(player, records, current)
    if remarked then return true, routineReason end
    local walked, followReason = followPulse(player, records, current, inVehicle)
    if walked then return true, followReason end
    return false, jokeReason or routineReason or followReason
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

function Banter._intrusiveForTests(actor, commands, records, current, kind)
    return intrusivePulse(actor, commands, records, current, kind)
end

return Banter
