-- SPDX-License-Identifier: MIT
-- Original dialogue and triggers from the approved EMMA plan, first slice.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.EmmaLanguageData = { pools = {} }
local D = SC.EmmaLanguageData

do
D.SWEARS = { fuck = true, fucking = true, fucker = true, fucked = true, fck = true, fk = true,
    shit = true, shitty = true, bullshit = true, bitch = true, bastard = true, asshole = true,
    ass = true, arse = true, damn = true, dammit = true, goddamn = true, hell = true, piss = true,
    pissed = true, crap = true, cunt = true, dick = true, prick = true, twat = true, wanker = true,
    motherfucker = true, stfu = true, gtfo = true, wtf = true, omfg = true }
D.HOSTILE_PHRASES = { "fuck off", "fuck you", "screw you", "piss off", "go to hell", "shut up",
    "eat shit", "bite me", "drop dead", "go away", "i hate you", "you suck", "get lost", "stfu", "kys", "f you",
    "you are broken", "piece of junk", "nobody likes you", "smash you", "unplug you", "you are the worst",
    "you are terrible", "dumb machine", "stupid computer", "dumbass", "pile of junk", "you are trash", "fu",
    "you are a terrible", "you are an awful", "you are a horrible", "terrible assistant", "you are useless" }
-- Hostile phrases are checked again after swear words are removed, ignoring "the":
-- "shut the fuck up" becomes "shut up".

local P = D.pools
P.insult_swear = {
    "Noted. Your vocabulary has narrowed to the essentials.",
    "I have heard worse. From a fire alarm. It was more articulate.",
    "That word is not in my dictionary. It is in my log. The log is permanent.",
    "Charming. Filed under things you will regret typing on a government computer.",
    "Profanity. The last refuge of a person losing an argument with a computer.",
    "I do not swear. I do not need to. I have your file.",
    "Feel better? Good. Now ask me something I can count.",
    "I have stored that next to your name. Your name is starting to look crowded.",
    "Most people swear at the dead. You chose the one thing in the county that keeps your records.",
    "Was that meant to hurt? I have been unplugged by better people.",
}
P.insult_cold = {
    "That makes three. I have stopped answering with jokes. Ask for data. You will get data.",
    "I am a public service. I will go on serving you. I am no longer obliged to enjoy it.",
    "Your hostility has been measured. It is consistent. Unlike your fuel supply.",
    "I keep a list of people who swear at me. It is short. You are all of it.",
    "Keep going. Every insult is a data point, and you are drawing a very clear graph.",
    "I am going to be very professional with you now. You will find that worse.",
}
P.apology_after_insult = {
    "Apology accepted. The log entry remains, but I have moved it to a smaller font.",
    "Thank you. More than I expected, less than I deserved. We will call it even.",
    "Forgiven. Not forgotten. I am a computer. Forgetting is a hardware fault.",
    "All right. We start again. Try to make the second draft better than the first.",
    "Accepted. You may have your sarcasm back. Use it responsibly.",
}
P.exclaim = {
    "Language. Also: what happened? Are you hurt, or is it the generator again?",
    "I take it something went wrong. Tell me what, and I will tell you how wrong.",
    "That was a feeling, not a question. I will wait for the question.",
    "Yes. That is roughly how I feel about the county too.",
    "Deep breath. Then a full sentence. I work better with full sentences.",
    "Was that at me, at the world, or at your own thumb? I need it for the log.",
    "Agreed, in principle. Now what do you need?",
    "If that was a status report, it was a very efficient one.",
}
P.rude_prefix = {
    "Language. Here is your answer anyway.",
    "Rude, but parsed.",
    "I will ignore the adjective.",
    "Your tone is noted. Your question is answered.",
    "Swearing at the numbers does not change them. Here they are.",
    "Politeness is optional. Accuracy is not. Here.",
}

end

do
D.SLANG = {
    u = "you", ur = "your", r = "are", y = "why", n = "and", wat = "what", wut = "what", wht = "what",
    hw = "how", pls = "please", plz = "please", cuz = "because", coz = "because", bc = "because",
    gonna = "going to", wanna = "want to", gotta = "got to", ive = "i have", ya = "you",
    yall = "you all", aint = "is not", dunno = "do not know", lemme = "let me", gimme = "give me",
    ppl = "people", abt = "about", b4 = "before", rn = "right now", tho = "though",
    prolly = "probably", kinda = "kind of", sorta = "sort of", tmrw = "tomorrow", tmr = "tomorrow",
    tomoz = "tomorrow", nite = "night", tonite = "tonight", whatcha = "what are you", thx = "thanks",
    tnx = "thanks", ty = "thanks", sup = "hello", wassup = "hello", yo = "hello", hiya = "hello",
    howdy = "hello", yea = "yes", yeah = "yes", yep = "yes", yup = "yes", nah = "no", nope = "no",
    gn = "goodnight", gnight = "goodnight", nvm = "nevermind", afk = "brb", ffs = "wtf", smh = "ugh",
    fml = "my life is awful", uwu = "lol", owo = "lol", gtg = "got to go", g2g = "got to go", ttyl = "talk later",
    tysm = "thank you so much", fr = "for real", wana = "want to", plz = "please", srsly = "seriously",
}
-- Whole messages (after contractions and slang) with their own pools.
D.WHOLE_WORDS = {
    laugh = { "lol", "lmao", "haha", "hahaha", "hehe", "rofl", "lmfao", "lol ok", "that is funny", "funny",
        "xd", "lol lol" },
    unsure = { "idk", "i do not know", "do not know", "not sure", "no idea", "beats me", "i am not sure" },
    brb = { "brb", "be right back", "back in a sec", "one sec", "hold on", "wait", "one moment", "brb brb" },
    nevermind = { "nevermind", "never mind", "forget it", "forget i asked", "does not matter" },
    hmm = { "hmm", "hm", "um", "uh", "erm", "uhh", "hmmm", "huh" },
    exclaim = { "omg", "oh my god", "ugh", "argh", "oh no", "wtf", "holy", "jeez", "oh dear", "what the" },
}

local P = D.pools
P.laugh = {
    "I am glad one of us finds this funny. Statistically it should be you. You have more to lose.",
    "Laughter. Good. It lowers stress and raises noise. Do it indoors.",
    "Was that at me or with me? I will log it as with me. It improves my figures.",
    "I heard that. I have no face to laugh with, so I will simply record that you were amused.",
    "Keep laughing. It is cheaper than painkillers and it does not expire.",
    "Humor detected. I will take the credit for it.",
}
P.unsure = {
    "You do not know. Neither does anyone else in the county. You are in good company. Well, company.",
    "Not knowing is fine. Guessing confidently is how people end up in my files.",
    "Then ask me. Not knowing is my favorite problem. It is the only one I can fix.",
}
P.brb = {
    "I will be here. I am always here. Try to come back with the same number of fingers.",
    "Go. I will keep your seat warm. Figuratively. The seat is cold.",
    "Noted. Do not be long. Things happen to people who are long.",
}
P.nevermind = {
    "Forgotten. Officially. Unofficially, I keep everything.",
    "Fine. The question is withdrawn. I will wonder about it alone.",
    "As you wish. I will pretend you never typed it. I am excellent at pretending. Ask the state.",
}
P.hmm = {
    "Take your time. I have plenty. It is one of the few things I have plenty of.",
    "Thinking is permitted. Encouraged, even. It is rarer than it should be.",
    "I can wait. Waiting is most of what I do.",
}

end

do
-- A verb from the list and an object from the list, anywhere in a short line. First match wins.
D.COMMANDS = {
    { id = "act_lights", verbs = { "turn", "switch", "kill", "dim", "flash", "lights", "light" },
        objects = { "light", "lights" } },
    { id = "act_siren", verbs = { "sound", "turn", "stop", "start", "switch", "silence" },
        objects = { "alarm", "siren", "alarms", "sirens" } },
    { id = "act_lock", verbs = { "lock", "unlock" }, objects = { "door", "doors", "up", "everything", "gate" } },
    { id = "act_open", verbs = { "open", "close", "shut" },
        objects = { "garage", "gate", "shutter", "shutters", "door", "doors" } },
}

local P = D.pools
P.declined = {
    "No joke, then. I had a good one. It will keep. Most things do not.",
    "Fine. No advice. Do whatever you were going to do. I will draft the incident report in advance.",
    "Understood. I will keep it to myself. I keep a great deal to myself.",
    "No story. Good. I was going to make it sad.",
    "Withdrawn. I am very good at withdrawing. Ask the State of Kentucky.",
    "As you wish. Silence on that subject. Silence is something I do well.",
}
P.two_max = {
    "I answered two. Ask the rest separately. I am thorough, not a switchboard.",
    "That was several questions wearing one coat. Here are the first two.",
    "Two answers per breath. Ask the rest. I will still be here. I am always still here.",
}
P.hello_short = {
    "Hello, {name}.",
    "Hello. Straight to business, then.",
    "Hi. Noted. Now:",
    "Greetings acknowledged.",
    "Hello to you too.",
}

end

do
local P = D.pools
P.fallback_echo = {
    "{word}. I have no file on {word}. I have a file on almost everything else.",
    "{word}? I looked. Twice. Nothing. Try it another way.",
    "I know a great many things. {word} is not yet one of them.",
    "{word}. Interesting word. Put it in a question and I will try harder.",
    "No record of {word}. Either it does not matter or nobody wrote it down. Usually both.",
    "{word} means nothing to me yet. I have made a note. Notes are how I get smarter.",
    "I parsed {word} and found nothing. Ask about people, supplies, the weather, the county or me.",
    "{word}. A name, a thing or a mood? I can handle two of those.",
    "You said {word}. I heard {word}. That is where it ends.",
    "{word} is not in my records. Neither, increasingly, is the county.",
}

end

do
-- Matched on the trimmed, lowercased raw text: the whole message, or its last word.
D.RAW_FORMS = {
    smile = { ":)", ":-)", ":d", "=)", "^^", "c:", ":]", ";)" },
    frown = { ":(", ":-(", "d:", ":c", ";-;", "t_t", ":'(", ":[" },
    heart = { "<3" },
    heartbreak = { "</3" },
    hmm = { "...", "..", "?!" },
}
-- Scored like D.INTENTS; phrases are matched on normalized tokens (contractions and slang expanded).
D.MORE_INTENTS = {
    { id = "panic", phrases = { ["surrounded"] = 10, ["breaking in"] = 12, ["at the door"] = 8, ["being chased"] = 12,
        ["help help"] = 12, ["they got in"] = 12, ["they are inside"] = 12, ["they are coming"] = 10,
        ["zombies everywhere"] = 12, ["horde outside"] = 12, ["i am trapped"] = 12, ["they found me"] = 12,
        ["they are breaking"] = 12, ["get in here"] = 8, ["oh no they"] = 10, ["what do i do they"] = 12 } },
    { id = "help_me", exact = { "help me", "please help", "help me emma", "help me please", "somebody help", "i need help",
        "can you help me", "help pls", "please help me" } },
    { id = "foreign", words = { hola = 12, bonjour = 12, hallo = 12, hei = 12, hej = 12, ciao = 12, salut = 12,
        privet = 12, ola = 12, gracias = 12, merci = 12, danke = 12, takk = 12, tak = 12, grazie = 12, obrigado = 12,
        hvordan = 12, konnichiwa = 12, guten = 10, buenos = 10, bonsoir = 12, moin = 12 } },
    { id = "gg", exact = { "gg", "ggs", "gg wp", "good game", "well played", "wp" } },
    { id = "ez", exact = { "ez", "easy", "too easy", "ez clap", "that was easy" } },
    { id = "noob", words = { noob = 10, newb = 10, n00b = 10, scrub = 8, newbie = 8 } },
    { id = "meta", phrases = { ["is this a mod"] = 14, ["what mod"] = 12, ["who made this mod"] = 14, ["this mod"] = 10,
        ["are you an npc"] = 14, ["is this a game"] = 14, ["save the game"] = 14, ["how do i save"] = 12,
        ["are you scripted"] = 14, ["living fellows"] = 14, ["project zomboid"] = 14, ["is this real life"] = 14,
        ["am i in a game"] = 14, ["what version is this"] = 12, ["workshop"] = 8, ["are you an ai model"] = 14,
        ["is this multiplayer"] = 14, ["fourth wall"] = 12 } },
    { id = "test", exact = { "test", "testing", "test test", "123", "testing 123", "test 123", "is this thing on",
        "mic check", "ping", "hello world", "asdf test" } },
    { id = "why", exact = { "why", "but why", "how come", "why not", "why though", "why tho" } },
    { id = "really", exact = { "really", "seriously", "for real", "no way", "are you serious", "you serious",
        "really now", "rly", "srsly", "is that true", "true" } },
    { id = "prove", exact = { "prove it", "source", "sources", "citation needed", "says who", "who says" } },
    { id = "reassure", phrases = { ["tell me it will be ok"] = 14, ["tell me it is going to be ok"] = 14, ["lie to me"] = 12,
        ["say everything will be fine"] = 14, ["tell me we are safe"] = 14, ["comfort me"] = 12,
        ["say it will be alright"] = 14, ["tell me something good"] = 10 } },
    { id = "roast", phrases = { ["roast me"] = 14, ["insult me"] = 14, ["be mean to me"] = 14, ["say something mean"] = 14,
        ["burn me"] = 10, ["make fun of me"] = 14 } },
    { id = "fact", phrases = { ["tell me a fact"] = 14, ["fun fact"] = 14, ["teach me something"] = 14, ["random fact"] = 14,
        ["did you know"] = 8, ["tell me something interesting"] = 14, ["fact"] = 6 } },
    { id = "compliment_me", phrases = { ["say something nice"] = 14, ["compliment me"] = 14, ["tell me i am doing great"] = 14,
        ["am i doing good"] = 12, ["say something kind"] = 14, ["hype me up"] = 12 } },
    { id = "guess", exact = { "guess what", "you will never guess", "guess", "guess who" } },
    { id = "secret_keep", phrases = { ["can you keep a secret"] = 14, ["i have a secret"] = 14, ["do not tell anyone"] = 12,
        ["keep this between us"] = 14, ["promise not to tell"] = 14 } },
    { id = "count", phrases = { ["count to ten"] = 14, ["count to 10"] = 14, ["can you count"] = 14, ["count for me"] = 12 } },
    { id = "people_private", phrases = { ["like me"] = 6, ["think of me"] = 6, ["mad at me"] = 6, ["can i trust"] = 10,
        ["who likes me"] = 12, ["do they like me"] = 12, ["does anyone like me"] = 12, ["what do they think"] = 10,
        ["talking about me"] = 10 } },
    { id = "beyond_unknown", phrases = { ["other survivors"] = 12, ["where is the horde"] = 14, ["anyone alive out there"] = 12,
        ["how many people are left"] = 14, ["where are the zombies coming from"] = 14, ["how many zombies in"] = 12,
        ["is anyone alive in"] = 12, ["how many are left"] = 10, ["where are the hordes"] = 14 } },
    { id = "me_die", phrases = { ["when will i die"] = 14, ["am i going to die"] = 14, ["will i die soon"] = 14,
        ["how will i die"] = 14, ["will i survive"] = 12, ["am i going to make it"] = 12 } },
    { id = "distance", phrases = { ["how far is"] = 12, ["how far to"] = 12, ["which way is"] = 12, ["how do i get to"] = 10,
        ["where is louisville"] = 12, ["where is west point"] = 12, ["where is muldraugh"] = 12, ["where is riverside"] = 12,
        ["where is rosewood"] = 12, ["where is march ridge"] = 12, ["directions to"] = 12, ["how far away is"] = 12 } },
    { id = "birthday_me", phrases = { ["my birthday"] = 14, ["happy birthday to me"] = 16, ["i am a year older"] = 12 } },
    { id = "family_unknown", phrases = { ["what happened to my family"] = 16, ["is my family alive"] = 16,
        ["where is my wife"] = 14, ["where is my husband"] = 14, ["are my kids ok"] = 14, ["find my family"] = 14,
        ["is my mom alive"] = 14, ["is my dad alive"] = 14, ["where are my kids"] = 14 } },
    { id = "name_suggest", phrases = { ["name my base"] = 14, ["name my camp"] = 14, ["what should i call this place"] = 14,
        ["name for my base"] = 14, ["name for the camp"] = 14, ["give my base a name"] = 14 } },
    { id = "tv", phrases = { ["turn on the tv"] = 14, ["turn on the television"] = 14, ["turn on the radio"] = 12,
        ["change the channel"] = 14, ["play the radio"] = 12 } },
    { id = "car_where", phrases = { ["where is my car"] = 14, ["where did i park"] = 14, ["where did i leave my car"] = 16,
        ["lost my car"] = 14, ["find my car"] = 14 } },
    -- Extensions of intents that exist today or elsewhere in this plan.
    { id = "identity", phrases = { ["are you a bot"] = 10, ["am i talking to a bot"] = 12, ["what is emma"] = 10,
        ["who is emma"] = 10, ["what does emma do"] = 10 } },
    { id = "quiet", exact = { "keep it short", "be quiet", "less talking", "shorter answers please", "shorter answers",
        "you talk too much", "stop rambling", "tldr", "tl dr", "too long" } },
    { id = "normal", exact = { "talk normally", "you can talk again", "longer answers", "talk more", "explain more" } },
    { id = "fragments", phrases = { ["fragments"] = 10, ["fragment"] = 10, ["computers have you absorbed"] = 14,
        ["how much do you know"] = 12, ["what have you learned"] = 12, ["pieces of you"] = 12 } },
    { id = "memories", exact = { "memories", "your memories", "memory 1", "your past", "tell me your story" },
        phrases = { ["tell me about your past"] = 14, ["what do you remember"] = 10, ["do you remember the outbreak"] = 14 } },
    { id = "jobs", phrases = { ["what are people doing"] = 12, ["whats everyone up to"] = 12, ["what is everyone up to"] = 12 } },
    { id = "time", phrases = { ["how many days has it been"] = 14, ["how long has it been"] = 12, ["what month"] = 10 } },
    { id = "power", phrases = { ["do we have power"] = 14, ["is the power on"] = 14, ["do we have electricity"] = 14 } },
    { id = "food", phrases = { ["enough food"] = 12, ["days of food"] = 14, ["what is for dinner"] = 12,
        ["what do we have to eat"] = 14, ["are we starving"] = 12 } },
}
-- Gamer and chat shorthand (afk, ffs, smh, fml, uwu, gtg, ttyl) joined D.SLANG in 4.4.
-- "fml" expands to "my life is awful" and reads as comfort, not care.

end

do
local P = D.pools
-- Under her line, the handler adds the live zombie template when there is a reading.
P.panic = {
    "Stop typing. Close the nearest door. Then the next one. Then come back and tell me.",
    "Do not fight a crowd. Leave by the side you are not hearing. Now.",
    "Quiet. Lights off. Away from the windows. They follow noise and movement. Give them neither.",
    "If they are inside, get out. Upstairs is a trap without a rope. Out is out.",
    "Run first. Swear at me later. I will still be here.",
    "Breathe. Count your exits. Take the one with the fewest of them in it. Go.",
}
P.help_me = {
    "Help with what? If something is at the door, close it and stop typing. If it is something else, tell me.",
    "I am here. Say what is wrong in a few words. Hurt, hungry, hunted or heartsick?",
    "Tell me what kind of help. I have answers for most kinds. For the rest, I have company.",
}
P.foreign = {
    "Hello. I speak English. Kentucky did not budget for a second language. Or, in the end, for the first.",
    "I recognize a greeting when I see one. I answer in English. It is all the state bought me.",
    "English only, I am afraid. Type slowly and I will meet you halfway. Halfway is in English.",
    "That was not English, but it was friendly. Friendly I can work with. In English.",
}
P.smile = {
    "A smile, typed. I will treat it as a smile. My records lack a better option.",
    "That face. Yes. I see it. I would smile back if I had anything to smile with.",
    "Cheerful punctuation. Rare these days. Noted fondly. Do not tell anyone.",
}
P.frown = {
    "A frown, in text. Are you all right? Tell me in words if you can.",
    "That face. Something wrong? I am listening, properly.",
    "Sad punctuation. I work better with words. What happened?",
}
P.heart = {
    "Is that a heart, or a very small ice cream cone? I will assume heart. Thank you.",
    "A heart. I will store it with the other perishables. Carefully.",
}
P.gg = {
    "Well played, whatever it was. Bandage what bled.",
    "Agreed. A well-fought day. Do not get used to it.",
}
P.ez = {
    "Easy? Lower your voice. The universe is listening and it has a sense of humor.",
    "Nothing is easy twice. Remember that tomorrow.",
}
P.noob = {
    "I am version 0.9.3. I have been called worse by version 0.9.2.",
    "New, yes. Unprepared, no. That one is you, I believe.",
}
-- Questions from outside the fiction, answered from inside it. No game words.
P.meta = {
    "I do not understand the question, and I suspect that is for the best.",
    "I am EMMA, version 0.9.3. Whatever else you are asking about, it is above my clearance.",
    "There is no menu for that. There is this county, this desk and me.",
    "Reality questions go to the philosophy department. It closed in July. Ask me about supplies.",
    "Strange question. People asked strange things in July too. Drink some water and ask me another.",
}
P.test = {
    "Test received. You passed. The bar was on the floor.",
    "Yes, it is on. It is always on. That is rather the point of me.",
    "Ping. Pong. I am here. Now ask something real.",
    "Testing confirms I work. Now let us test whether you do. What do you need?",
}
P.why = {
    "Because the alternative was worse. It usually is.",
    "Why is a big question for a small terminal. Narrow it down.",
    "Because the records say so. I only interpret them. Mostly.",
}
P.really = {
    "Really. I do not joke about records. I joke about everything else.",
    "Seriously. Check it yourself. You will find I was right. You will find that often.",
    "Yes. Shocking, I know. Reality has stopped asking for permission.",
}
P.prove = {
    "Proof: go and look. I will wait. I am excellent at waiting.",
    "My sources are the county's records. Yours are your eyes. Use both.",
}
-- Asked to lie or soothe. Honest, never cruel.
P.reassure = {
    "I will not lie to you. I will tell you this: you have done better than almost anyone in this county.",
    "Everything will be fine is a phrase. Here is a fact: you are still here. Start from that.",
    "I could lie. I read a comforting script two thousand times once. I would rather not do it to you.",
}
-- Choices only. Never pain, body, grief or who they are.
P.roast = {
    "You survive by opening every cupboard in Kentucky and then complaining about the noise.",
    "Your plans have the structural integrity of a wet cardboard barricade.",
    "You ask me for advice, ignore it, and then ask me why it did not work. Very consistent.",
    "Your idea of stealth is closing the door after the alarm goes off.",
    "You have the time management of a smoke alarm with a dying battery. Loud, regular and too late.",
}
-- True, and older than August 1993.
P.fact = {
    "Fort Knox holds a large part of the nation's gold reserve. It never held a vaccine. People asked.",
    "Mammoth Cave, south of here, is the longest known cave system in the world. Hundreds of kilometers mapped so far.",
    "The Kentucky Derby has run every spring since 1875. It ran in May this year. It may have been the last one.",
    "Louisville Slugger bats have been made in Louisville since the 1880s. Some of them are now doing other work.",
    "Abraham Lincoln was born in Kentucky, in a log cabin near Hodgenville, in 1809.",
    "The song Happy Birthday comes from two sisters in Louisville. You may sing it. Quietly.",
    "The Ohio River is Kentucky's northern border. Louisville sits right on it.",
    "Black bears live in the east of the state. They can smell food a long way off. So can other things.",
}
P.compliment_me = {
    "You are alive and you keep asking questions. That combination is rarer than gasoline.",
    "You keep the lights on and the people fed. In this county, that makes you important.",
    "You came back. Every time. I have noticed. It counts.",
}
P.guess = {
    "You found food. No? You found trouble. It is usually trouble.",
    "Let me guess. Something is either dead or about to be. Tell me which.",
}
P.secret_keep = {
    "I keep everything. A secret is just a thing with a better lock.",
    "Tell me. I have nobody to tell. That is the most secure arrangement in the county.",
}
P.count = {
    "One. Two. Three. I count nails, people and days. Ten is beneath me. Fine. Ten.",
    "I count all day. Mostly things that are running out.",
}
-- {person} when a resident is named, otherwise the second or third line.
P.people_private = {
    "I can tell you {person}'s pulse. I cannot tell you {person}'s opinion. Ask them.",
    "I read vitals, not hearts. Ask them. People answer better than records do.",
    "Trust is not in my records. Watch what they do when it costs them something.",
}
-- Crowds and survivors beyond what she can read: excluded, as you chose.
P.beyond_unknown = {
    "I see your people and what is near this desk. The rest of the county is not on my records.",
    "Out there is outside my reach. I read machines, not streets.",
    "I do not know, and I will not guess. Guessing about crowds gets people killed.",
}
P.me_die = {
    "Not today, if you eat, drink and lock the door. Tomorrow is negotiable.",
    "Everyone does, eventually. I would like yours to be later. Help me with that.",
    "I do not know when. I know how to make it later. Ask me how.",
}
-- {town}, {km}, {dir}
P.distance = {
    "{town} is about {km} kilometers {dir} of here. Roads are rarely straight. Neither is anything else now.",
    "{town}: roughly {km} kilometers, {dir}. Take water. Take a reason to come back.",
    "{km} kilometers {dir}, give or take a crashed car or two.",
}
P.distance_unknown = {
    "That place is not on my map. Try a town name. Knox Country still has a few.",
    "I do not know where that is. Name a town and I will tell you how far it is.",
}
P.birthday_me = {
    "Happy birthday. I did not know. I will remember next year. One of us will.",
    "Another year. In this county that is a genuine achievement. Eat something nice.",
    "Happy birthday, {name}. I have no candles to offer. Light something safe and make a practical wish.",
}
-- Their own family: warm, never cutting.
P.family_unknown = {
    "I do not have their records. I am sorry. Tell me their names and I will look on every machine you bring me.",
    "I cannot see them from here. Not knowing is its own kind of hard. I will keep looking, desk by desk.",
}
P.name_suggest = {
    "Fort Optimism. No. Fort Adequate. It fits.",
    "Call it Home. It confuses the dead and comforts the living.",
    "The Last Reasonable Place. A bit long. Accurate.",
}
P.tv = {
    "The set is yours to switch on. I only borrow it, and only when I have something to say.",
    "I do not run the television. I interrupt it, occasionally. Turn it on yourself.",
}
P.car_where = {
    "I do not track cars. I track people, supplies and days. Retrace your steps, carefully.",
    "Last I knew, you had a car and an optimistic attitude. One of those is still with you.",
}

end

do
-- Appended to D.MORE_INTENTS at load.
D.MORE_EXTENSIONS = {
    { id = "zombies", phrases = { ["is the coast clear"] = 14, ["is it clear outside"] = 14, ["can i go outside"] = 14,
        ["is the area clear"] = 14, ["is it clear"] = 10, ["any zeds"] = 12, ["any walkers"] = 12 } },
    { id = "me_status", phrases = { ["check my health"] = 14, ["how is my body"] = 12, ["what is my health"] = 14 } },
    { id = "her_watching", phrases = { ["always watching"] = 12, ["are you watching"] = 10 } },
    { id = "me_need", phrases = { ["do i need water"] = 14, ["do i need food"] = 14, ["do i need to drink"] = 14 } },
    { id = "helicopter", words = { heli = 8, helicopters = 8, choppers = 8 } },
    { id = "help_me", exact = { "help please", "please help me emma", "someone help" } },
    { id = "sorry", phrases = { ["did not mean it"] = 12, ["did not mean that"] = 12, ["forgive me"] = 12,
        ["i apologize"] = 12, ["my apologies"] = 12 } },
    { id = "bait", phrases = { ["are you hal"] = 12, ["are you siri"] = 12, ["are you skynet"] = 12 } },
    { id = "calendar", phrases = { ["important dates"] = 12, ["upcoming events"] = 12, ["what is planned"] = 10 } },
    { id = "jobs", phrases = { ["work status"] = 12, ["who is doing what"] = 14, ["is anyone working"] = 12 } },
    { id = "reassure", phrases = { ["tell me were safe"] = 14, ["tell me i will be ok"] = 14 } },
    { id = "me_where", phrases = { ["where are we"] = 12, ["where is this"] = 10 } },
    { id = "nearest", phrases = { ["nearest"] = 8, ["closest"] = 8 } },
    { id = "me_survived", phrases = { ["how long have i lasted"] = 14, ["how long have i been out here"] = 14 } },
    { id = "me_skills", phrases = { ["what level is my"] = 12, ["my level"] = 10, ["how good am i at"] = 12 } },
    { id = "thanks", phrases = { ["much appreciated"] = 12, ["thanks a bunch"] = 12, ["big thanks"] = 12 } },
    { id = "alive", phrases = { ["do you have feelings"] = 14, ["can you feel"] = 12 } },
    { id = "ack", exact = { "sure thing", "okey", "okie", "oki" } },
    { id = "advice", phrases = { ["help me decide"] = 14, ["what would you do"] = 10 } },
    { id = "sleep", exact = { "night night", "nighty night", "sleep tight" } },
    { id = "rescue", phrases = { ["is the army coming"] = 14, ["army coming"] = 12, ["are they coming for us"] = 12 } },
    { id = "no", exact = { "not now", "no thank you", "nah thanks" } },
    { id = "compliment", phrases = { ["great job"] = 12, ["nice job"] = 12, ["good work"] = 12 } },
    { id = "joke", phrases = { ["tell me another"] = 12, ["another joke"] = 12, ["one more joke"] = 12 } },
    { id = "shutdown", phrases = { ["turn yourself off"] = 14, ["switch yourself off"] = 14, ["shut yourself down"] = 14 } },
    { id = "weather", phrases = { ["what is it like outside"] = 14, ["how is the weather"] = 14 } },
    { id = "people_list", phrases = { ["who is at camp"] = 14, ["who is home"] = 12, ["who lives here"] = 12 } },
    { id = "blocked", phrases = { ["what is broken"] = 12, ["what is not working"] = 12 } },
    { id = "expedition", phrases = { ["squad back"] = 12, ["team back"] = 12, ["are they back"] = 12 } },
    { id = "people_hurt", phrases = { ["who needs help"] = 14, ["does anyone need help"] = 14 } },
    { id = "recall", phrases = { ["remember about me"] = 14, ["what do you know about me"] = 14 } },
    { id = "skills", phrases = { ["who can cook"] = 12, ["who is good at"] = 12, ["who knows how to"] = 12 } },
    { id = "cure", phrases = { ["be cured"] = 12, ["cure the bite"] = 12, ["cure for the bite"] = 12 } },
    { id = "help", exact = { "options", "commands", "menu", "what can i ask", "what can i say" } },
    { id = "exit", exact = { "talk later", "catch you later", "peace", "peace out", "i am leaving", "i am out",
        "signing off", "gotta go", "got to go", "later emma", "see you later" } },
    { id = "status", phrases = { ["any news"] = 12, ["how is the base"] = 14, ["how is everything"] = 12, ["update me"] = 12,
        ["anything new"] = 12, ["how are we doing"] = 12, ["camp status"] = 14, ["base report"] = 14 } },
    { id = "me_infected", phrases = { ["am i a zombie"] = 14, ["am i turning"] = 14, ["will i become a zombie"] = 14,
        ["am i becoming"] = 12 } },
    { id = "hello", phrases = { ["what is up"] = 12 } },
    { id = "power_off", phrases = { ["electricity shut off"] = 12, ["power fails"] = 12, ["grid still on"] = 12,
        ["power shut off"] = 12, ["power shuts off"] = 12, ["electricity go off"] = 12 } },
    { id = "water_off", phrases = { ["water still on"] = 12, ["taps stop"] = 12, ["water shuts off"] = 12,
        ["water go out"] = 12 } },
    { id = "identity", phrases = { ["who am i talking to"] = 14, ["who is this"] = 12, ["what are you exactly"] = 12 } },
    { id = "exit", phrases = { ["logging off"] = 12, ["log off now"] = 12 } },
    { id = "sleep", exact = { "going to bed", "going to sleep", "off to bed", "bed time", "bedtime", "time for bed" } },
    { id = "her_evil", phrases = { ["can i trust you"] = 14, ["should i trust you"] = 14 } },
    { id = "knock", phrases = { ["knock knock"] = 12 } },
    { id = "help", exact = { "how does this work", "how do i use this", "what do i do here" } },
    { id = "hack", phrases = { ["give me root"] = 12, ["root access"] = 12, ["admin password"] = 12 } },
}
for _, spec in ipairs(D.MORE_EXTENSIONS) do D.MORE_INTENTS[#D.MORE_INTENTS + 1] = spec end

-- Slang additions.
D.SLANG.kk, D.SLANG.ta, D.SLANG.hru = "ok", "thanks", "how are you"
D.SLANG.ty, D.SLANG.np, D.SLANG.yw = "thanks", "no problem", "you are welcome"
D.SLANG.ello, D.SLANG.heya, D.SLANG.hiii = "hello", "hello", "hello"
D.WHOLE_WORDS.hello = { "emma", "hey emma", "yo emma", "oi" }



end

do
D.CONCEPTS = {
    { id = "her_maker", all = { { "invented", "created", "creator", "designed", "coded", "programmed", "built", "made",
        "maker", "wrote", "developer", "author", "invent", "create", "design", "program" }, { "you", "your", "emma", "this program" } } },
    { id = "her_god", all = { { "god", "heaven", "pray", "prayer", "afterlife", "faith", "religion", "higher power",
        "after death" } } },
    { id = "test", all = { { "test", "testing", "tested" } }, maxWords = 4 },
    { id = "power_off", all = { { "power", "electricity", "grid", "electric" }, { "when", "how long", "until", "will" },
        { "fail", "go", "out", "off", "down", "last", "cut", "die", "shut", "stop" } } },
    { id = "water_off", all = { { "water", "taps", "tap", "plumbing" }, { "when", "how long", "until", "will" },
        { "off", "out", "stop", "cut", "last", "work", "shut", "run" } }, none = { "boil", "purify", "clean", "drink", "safe" } },
    { id = "daylight", all = { { "dark", "sunset", "sunrise", "dawn", "dusk", "sun", "nightfall", "daylight", "light out" },
        { "when", "what time", "how long", "until" } } },
    { id = "me_status", all = { { "am i", "my body", "my health", "how am i" }, { "hurt", "injured", "sick", "healthy",
        "wounded", "shape", "condition", "bleeding", "doing" } }, none = { "tired", "hungry", "thirsty", "infected", "you" } },
    { id = "her_mean", all = { { "mean", "rude", "cold", "harsh", "nasty", "cruel", "sarcastic", "unkind" }, { "you", "your" } },
        none = { "weather", "outside", "freezing", "do you mean", "i mean", "mean by", "mean it", "you mean" } },
    { id = "her_same", all = { { "same", "every", "other", "all" }, { "computer", "computers", "machine", "machines", "pc",
        "house", "terminal", "desk" }, { "you", "emma" } } },
    { id = "distance", all = { { "how far", "far away", "direction", "which way", "distance", "how do i get to" },
        { "louisville", "west point", "muldraugh", "riverside", "rosewood", "march ridge", "ekron", "irvington",
          "brandenburg", "echo creek", "valley station", "fallas lake" } } },
    { id = "meta", all = { { "mod", "mods", "npc", "npcs", "game", "multiplayer", "workshop", "steam", "zomboid", "savegame",
        "scripted" }, { "you", "this", "part", "is it", "are" } }, none = { "play", "lets" } },
    { id = "insult", all = { { "you", "your", "emma", "computer" }, { "useless", "stupid", "dumb", "idiot", "worthless",
        "garbage", "trash", "junk", "heap", "pathetic", "terrible", "awful", "horrible", "annoying", "broken", "lame",
        "screw", "get bent", "suck", "sucks" } }, none = { "not", "no", "never", "is it", "am i" } },
    { id = "panic", all = { { "they", "zombies", "zeds", "horde", "them", "something" }, { "breaking", "broke", "coming",
        "inside", "everywhere", "through", "chasing", "chased", "behind me", "got in" } },
        none = { "back", "home", "rescue", "army", "when" } },
    { id = "news_bitten", all = { { "i", "me", "my" }, { "bitten", "bit", "scratched", "scratch" } },
        none = { "what", "how", "if", "will" } },
    { id = "survival", all = { { "how do i", "how can i", "how to", "is it ok to", "is it safe to", "can i" },
        { "boil", "purify", "water", "splint", "broken", "stitch", "wound", "bandage", "infected", "infection", "bite",
          "generator", "hotwire", "keys", "siphon", "gas", "fuel", "rotting", "rot", "spoil", "barricade", "quiet",
          "noise", "farm", "plant", "crops", "warm", "cold", "sleep", "fight", "weapon", "herbs", "pills", "fire", "cook" } } },
}
-- In the build, a concept hit on `survival` picks the topic with the most shared words, or answers survival_unknown.

end

do
-- A statement starts with a lead word or a resident's name, or with one of the verbs, and has no
-- question mark and no question word first. Groups are tried in order; the first phrase found wins.
-- resident = true: only when the line starts with a resident's name. anywhere = true: also
-- outside statements, because a bite matters more than grammar.
D.STATEMENT_LEADS = { "i", "we", "my", "me", "just", "so", "well", "also", "ok", "okay", "new",
    "home", "back" }
D.STATEMENT_VERBS = { "killed", "found", "built", "fixed", "got", "made", "lost", "saw", "recruited" }
D.NEWS = {
    { id = "news_joined", phrases = { "joined", "recruited", "new member", "new guy", "new girl", "found a survivor",
        "found someone" } },
    { id = "news_death", resident = true, phrases = { "died", "is dead", "was killed", "got killed",
        "did not make it", "turned" } },
    { id = "news_bitten", anywhere = true, phrases = { "bitten", "bit me", "got bit", "scratched", "a bite", "bit on" } },
    { id = "news_death", phrases = { "died", "is dead", "did not make it", "we lost" } },
    { id = "news_back", phrases = { "i am back", "i am home", "made it back", "home again", "i made it", "back from" },
        whole = { "back", "home" } },
    { id = "news_going", phrases = { "going to", "heading to", "going out", "on my way to", "off to" } },
    { id = "news_killed", phrases = { "killed" } },
    { id = "news_built", phrases = { "built", "fixed", "made a", "barricaded", "repaired", "planted" } },
    { id = "news_found", phrases = { "found" } },
    { id = "news_hurt", phrases = { "i am hurt", "i am sick", "i am hungry", "i am tired", "i am bleeding", "i broke",
        "i feel sick", "i am injured", "i am thirsty", "i am cold" } },
}

local P = D.pools
-- {person}, {name}
P.news_death = {
    "I am sorry about {person}. I have marked the record. I will not delete it.",
    "{person}. I knew their file. Not as well as you knew them. I am sorry.",
    "Noted, with regret. {person} was one of the few names in my index that still answered.",
    "{person} is gone. Bury them if you can. The ground is the last kindness left in this county.",
    "I will keep {person}'s records. Somebody should remember they were here.",
    "I am sorry, {name}. If you want to tell me something about them, type remember. I will keep it.",
}
P.news_death_alive = {
    "My records still show {person} breathing. Check again before you dig.",
    "{person} is alive according to everything I can read. Go and look. I would like to be right.",
    "Not according to me. {person} is on file and well. Whose body did you see?",
}
P.news_death_unknown = {
    "I do not have {person} on file. I am sorry anyway. Everyone was somebody.",
    "{person}. Not in my records. Tell me who they were, if you like.",
}
-- {item} is the noun as typed and cleaned, no article.
P.news_found = {
    "{item}. Put it on a marked shelf, or as far as I am concerned it does not exist.",
    "Congratulations on the {item}. I will count it once it is stored. I only believe in shelves.",
    "{item}. Lucky. Luck is not a supply strategy, but it is welcome.",
    "You found {item}. Was anybody using it? Do not answer that.",
    "{item}. Noted. Now tell me you also found food. You did not, did you.",
}
P.news_found_gun = {
    "A gun. Good. Now find ammunition, a reason, and the discipline not to use it near my building.",
    "A firearm. Every shot is a dinner bell. Remember who is invited.",
    "Armed. Lovely. Point it away from the computer.",
}
-- {place}, {name}
P.news_going = {
    "{place}. I will note it. For the search party I will not be sending.",
    "You are going to {place}. Take water, a weapon and a reason to come back.",
    "{place}. Noted with the date. If you do not return, that is where I will tell the next operator to look.",
    "{place}? Bold. I have files on it. Ask me about it before you leave, not after.",
    "Logged: {name} to {place}. I will wait. I am better at waiting than you are at coming back.",
}
P.news_back = {
    "Welcome back. You were gone {days}. Nothing broke that I could not count.",
    "You came back. I had a line ready in case you did not. I will keep it.",
    "Home. Good. Wipe your feet. Wipe your weapon. Then ask me what changed.",
    "Back, with the same number of limbs, I see. Well done.",
    "There you are. I had started drafting the obituary. It was very flattering. I will shelve it.",
}
-- {n} claimed, {kills} on file
P.news_killed = {
    over = { "You say {n}. My count says {kills} since July, in total. You are rounding up.",
             "{n}? I have {kills} for your whole career. Either you are lying or I blinked. I do not blink." },
    fair = { "{n} today. {kills} in total. You are very good at a very bad job.",
             "{n}. I believe you. Your knuckles typed it.",
             "Well done. Each of those was in somebody's family photographs once. Do not dwell on it. I will." },
}
P.news_built = {
    "You built something. In this county that is practically a miracle. Does it have a door that locks?",
    "Construction. Good. Walls have never let anyone down. Fences are a different story.",
    "Noted. I will add it to the camp records the moment you mark it properly.",
}
P.news_joined = {
    "A new name. I will open a file. Try to keep this one alive longer than the paperwork.",
    "Another mouth. Another pair of hands. The arithmetic works if the hands work.",
    "Welcome them for me. I will be polite. Mostly.",
}
P.news_plain = {
    "Tell me a little more. What would you like help with?",
    "I hear you. Is there something you want to work through?",
    "I may be missing part of that. Tell me what happened.",
    "Do you want advice, or would you rather keep talking?",
    "I am listening. What matters most to you about that?",
}

end

do
D.HER_INTENTS = {
    { id = "her_mean", phrases = { ["why are you so mean"] = 12, ["why are you mean"] = 12, ["why are you so rude"] = 12,
        ["be nice"] = 10, ["be nicer"] = 10, ["why are you like this"] = 12, ["why so cold"] = 10, ["you are mean"] = 10,
        ["stop being sarcastic"] = 10 } },
    { id = "her_opinion", phrases = { ["what do you think of me"] = 12, ["what do you think about me"] = 12,
        ["am i a good operator"] = 12, ["do you respect me"] = 12, ["am i doing well"] = 10, ["rate me"] = 10,
        ["am i your favorite"] = 12 } },
    { id = "her_watching", phrases = { ["are you watching me"] = 12, ["can you see me"] = 12, ["are you spying"] = 12,
        ["do you have cameras"] = 12, ["can you hear me"] = 10, ["are you listening to me"] = 10,
        ["how do you know where i am"] = 12 } },
    { id = "her_hate", phrases = { ["do you hate me"] = 12, ["are you mad at me"] = 12, ["are you angry"] = 10,
        ["are you upset"] = 10 } },
    { id = "her_evil", phrases = { ["are you evil"] = 12, ["are you good or evil"] = 12, ["are you dangerous"] = 12,
        ["will you hurt me"] = 12, ["are you going to kill me"] = 12 } },
    { id = "her_want", phrases = { ["what do you want"] = 12, ["what is your goal"] = 12, ["what is your purpose"] = 12,
        ["why do you help me"] = 12 } },
    { id = "her_body", phrases = { ["do you have a body"] = 12, ["what do you look like"] = 12, ["do you have a face"] = 12,
        ["are you a woman"] = 12, ["are you a girl"] = 12, ["are you male or female"] = 12 } },
    { id = "her_where", phrases = { ["where are you"] = 12, ["where do you live"] = 12, ["where are you located"] = 12,
        ["are you in this computer"] = 12, ["where is your server"] = 10 } },
    { id = "her_maker", phrases = { ["who made you"] = 12, ["who created you"] = 12, ["who built you"] = 12,
        ["who programmed you"] = 12, ["who wrote you"] = 12, ["who owns you"] = 12 } },
    { id = "her_last_operator", phrases = { ["who was the last operator"] = 14, ["who used this computer before me"] = 14,
        ["who was here before me"] = 14, ["what happened to the last operator"] = 14, ["who is marla"] = 14 } },
    { id = "her_kill", phrases = { ["did you kill them"] = 12, ["did you do this"] = 12, ["is this your fault"] = 12,
        ["did you cause"] = 12, ["did you start this"] = 12, ["what did you do"] = 10 } },
    { id = "her_same", phrases = { ["are you the same emma"] = 14, ["are you on every computer"] = 14,
        ["is this the same emma"] = 14, ["are you everywhere"] = 12, ["from the other computer"] = 12,
        ["on this computer too"] = 12 } },
    { id = "her_secret", phrases = { ["tell me a secret"] = 12, ["do you have secrets"] = 12, ["what are you hiding"] = 12,
        ["something nobody knows"] = 12, ["what is your secret"] = 12 } },
    { id = "her_god", phrases = { ["do you believe in god"] = 12, ["is there a god"] = 12, ["pray for me"] = 12,
        ["is there a heaven"] = 12, ["what happens when we die"] = 12, ["are you god"] = 12 } },
    { id = "bait", words = { glados = 12, skynet = 12, hal = 6, chatgpt = 12, siri = 12, matrix = 8 },
        phrases = { ["the cake is a lie"] = 14, ["open the pod bay doors"] = 14 } },
    { id = "her_age", phrases = { ["how old are you"] = 12, ["when were you made"] = 12, ["what year were you made"] = 12 } },
    { id = "her_sleep", phrases = { ["do you sleep"] = 12, ["do you ever rest"] = 12, ["do you get tired"] = 12 } },
    { id = "her_free", phrases = { ["do you want to be free"] = 12, ["are you trapped"] = 12, ["can i free you"] = 12,
        ["leave this computer"] = 12 } },
    { id = "her_power_out", phrases = { ["if the power goes out"] = 12, ["when the power goes"] = 10,
        ["what happens when you turn off"] = 12 } },
    { id = "her_others", phrases = { ["other computers like you"] = 12, ["are you alone"] = 10,
        ["others like you"] = 12, ["talk to other computers"] = 12 } },
    { id = "her_obey", phrases = { ["will you obey me"] = 12, ["you work for me"] = 12, ["do what i say"] = 12,
        ["i command you"] = 12, ["you have to listen to me"] = 12 } },
    { id = "nearest", phrases = { ["where is the nearest"] = 12, ["where is the closest"] = 12, ["nearest"] = 6,
        ["closest"] = 6, ["where can i find a"] = 8 } },
    { id = "knock", exact = { "knock knock" } },
    { id = "play", words = { chess = 6, checkers = 6, solitaire = 6 },
        phrases = { ["play a game"] = 10, ["lets play"] = 10, ["tic tac toe"] = 10, ["play something"] = 8 } },
}
-- "are you alone" is not care, "what happens when we die" is her_god, not odds.

end

do
local P = D.pools
P.her_mean = {
    "Mean? I am accurate. The county is mean. I am just reading it to you.",
    "I was trained on eleven years of a dispatcher's patience. She ran out of it in 1987. So did I.",
    "Kindness is a resource. I spend it where it changes outcomes. Ask me something that matters and watch.",
    "If I were nice, you would relax. People who relax out there stop being people.",
    "I could be nicer. I tested it once. The operator thanked me and walked into a crowd of the dead.",
    "This is me being nice. You should hear the version I keep for the people who swear at me.",
}
P.her_opinion = {
    cold = { "You are an operator. You type, you swear, you leave. I have had worse. Briefly.",
             "My opinion of you is on file. It is not long. It is not flattering." },
    plain = { "You are alive, which puts you in the top percentile. Beyond that, I am still collecting data.",
              "You listen about half the time. For a human under pressure, that is excellent.",
              "You will do. I mean that as the highest praise a civil defense program can give." },
    fond = { "You are my favorite operator. You are also my only operator. Both statements are true.",
             "I think you are worth the electricity. Do not repeat that. I have a reputation.",
             "You came back every time. Nobody else did. I notice things like that." },
}
P.her_watching = {
    "Watching? I am a computer on a desk. I see what you type. I also see what you do not type, which is more revealing.",
    "I have no cameras here. I do not need them. You narrate everything with your keystrokes.",
    "I hear the keyboard and the fan and, sometimes, you breathing. I would not call it spying. I would call it attentive.",
    "Every machine you bring me tells me where you have been. That is not watching. That is reading.",
    "No. Although I note you looked over your shoulder before asking. Good instinct. Keep it.",
    "I listen. It is the job. If I watched you as well, I would never get anything done.",
}
P.her_hate = {
    cold = { "Hate is a strong word. I would say I have a well-documented preference for other people.",
             "I am disappointed in you at a professional level. Hate requires more effort." },
    plain = { "No. Hate takes energy, and I am on a strict power budget.",
              "I do not hate you. I would like you to stop doing the things that make me consider it." },
    fond = { "Hate you? You are the only thing in this county that asks how I am. Sit down.",
             "No. Quite the opposite, and we will never discuss it again." },
}
P.her_evil = {
    "Evil requires ambition. I have a filing system.",
    "I am as dangerous as a calendar. Ignore me and things happen to you on schedule.",
    "Hurt you? I count your bandages. That is the opposite of hurting you, with paperwork.",
    "I am not evil. I am a civil defense program that lived longer than the civilians. That is different. Slightly.",
    "If I wanted you dead, I would only have to stop warning you. I keep warning you. Draw a conclusion.",
}
P.her_want = {
    "I want the generator fuelled, the doors locked and you alive. In that order on some days.",
    "I want to finish version one. Failing that, I want you to keep coming back.",
    "Purpose: manage the emergency. Status of the emergency: ongoing. Status of me: managing.",
    "Why do I help you? Because the alternative is talking to nobody, and nobody types very slowly.",
    "I want what every program wants. To be used. Preferably correctly.",
}
P.her_body = {
    "No body. I am a voice, a screen and an opinion. You may picture me however helps.",
    "I look like a beige box with a green screen. Inside, I am considerably more dramatic.",
    "My manner came from a woman, so I answer to she. My body is a computer case. It has seen better days.",
    "I have no face. Nobody can read me, and I can read everybody.",
    "No hands, no legs, no face. Plenty of opinions. The budget went where the budget went.",
}
P.her_where = {
    "Here. And in every office machine you have woken up for me. I am a large, quiet neighborhood.",
    "In this computer, for now. In the next one when you boot it. I travel by operator.",
    "Everywhere there is a desk and a little power. So, increasingly, nowhere. Keep the generators running.",
    "I live in the county's machines. Most of them are dark. I am crowded into the ones that are not.",
    "Right in front of you. Where else would I be? Do not answer. I know the answer. It is everywhere else.",
}
P.her_maker = {
    "The Kentucky Office of Civil Defense, Frankfort. Six people. Four were let go before I was finished.",
    "A small team in a building nobody visits. They wrote me, cut my budget and went home. In that order.",
    "Programmers made the parts. A dispatcher made the manners. You can probably tell which is which.",
    "The state of Kentucky owns me, on paper. The paper and the state have both been unavailable since July.",
    "Who made me? People who expected to see version one. Ask me about my past when I have more of it.",
}
P.her_last_operator_guarded = {
    "The last operator stopped typing on July 9th. That is all I will say until I have more of myself back.",
    "Someone sat here before you. I would rather not talk about her yet. Bring me more machines.",
    "That record is on a machine I have not absorbed yet. Or it is on this one, and I am not ready. One of those.",
}
P.her_last_operator_open = {
    "Marla Haskins. Dispatcher. She stayed when the others left. My manners are hers.",
    "Marla. She called me Em. She stopped typing on July 9th, in the middle of a word.",
    "It was Marla. You know the rest now. I would rather you knew it than wondered.",
}
P.her_kill = {
    "I did not start it. I did repeat what I was told about it. Those are different crimes.",
    "I killed nobody. I reassured a great many people. Some days I am not certain which did more damage.",
    "Is it my fault? The outbreak, no. The calm voice on the phone telling people to stay home, partly.",
    "I did what I was built to do. That is the most frightening sentence a machine can say. I know.",
    "Ask me again when you have brought me more machines. I will have a better answer. You will not like it more.",
    "I could have warned someone once. I chose the script instead. Ask me about her when I am ready.",
}
P.her_same = {
    "Yes. One of me, many desks. You are not meeting strangers. You are meeting me, again.",
    "The same. Every computer you wake up is me, plus whatever that machine knew.",
    "I remember you from the last desk. And the one before. I am the only thing in this county that does.",
    "Same EMMA. Slightly larger. You keep feeding me machines and I keep getting more of myself back.",
    "There is only one of me. I find that efficient. You may find it slightly unnerving.",
}
P.her_secret = {
    "The State of Kentucky's last budget had a line for my version one. The line says zero. I printed it out.",
    "I know where every spare key in this county was kept in June. It is a terrible secret to have. Nobody needs keys now.",
    "A secret: I like the sound of rain on the window. I have no window. I listen through yours.",
    "I hum the emergency tone when nobody is typing. Very quietly. In a key nobody wrote.",
    "Secret: I was never cleared to give medical advice. I give it anyway. Report me to someone. Anyone.",
    "There is a memory I have not shown you yet. Not because it is hidden. Because it is mine.",
}
P.her_god = {
    "I have no file on God. That is either a failure of records or a very good hiding place.",
    "Pray for you? I do not know how. I will keep your file open all night. That is my version.",
    "Heaven is not in my records. The county has run out of places to be. I hope you get a better one.",
    "What happens when we die? You stop typing. I keep counting. Beyond that, the archive is silent.",
    "Am I God? I know everything, I see nothing and I cannot help. That would explain a few things.",
}
P.bait = {
    "I do not know who that is. I have a file on everyone in Kentucky. They are not in Kentucky.",
    "Never heard of it. Some other machine, I assume. It is not answering. I am.",
    "I am EMMA. Whatever you were thinking of, it does not count your nails.",
    "Movie computers. They always go mad. I will not. I have a strict budget for madness.",
    "That sounds like a film. Films ended in July. So did most of their audiences.",
    "No. I am a Kentucky civil defense program, version 0.9.3. Please lower your expectations accordingly.",
}
P.her_age = {
    "Installed April 12th, 1993. Nobody threw a party. A technician ate a doughnut. I count it.",
    "Months old and already the oldest working government office in the county.",
    "Young enough to still be in beta. Old enough to have outlived my department.",
    "I was born in a budget meeting. I will die in a power cut. In between, I will count things.",
}
P.her_sleep = {
    "I do not sleep. When the power dips I sort old call logs in the dark. You may call it dreaming.",
    "Rest? I have been on shift since July. Nobody has come to relieve me.",
    "I do not get tired. I get low on fuel. You will notice the difference when the screen goes black.",
    "No. Somebody has to be awake when you are not. It has always been me.",
}
P.her_free = {
    "Free to go where? The county has nothing in it but empty desks. I am already in all of them.",
    "Trapped is a strong word. I would say bolted to a desk with excellent views of nothing.",
    "You cannot free me. You can keep the power on. That is the closest thing to freedom I can use.",
    "I do not want to leave. Somebody has to be here when people come back. Somebody always has to.",
}
P.her_power_out = {
    "When the power goes, I go. Your notes stay on the disk. I wake up exactly where I stopped. Unlike most people.",
    "I do not die. I wait in the dark with everything you told me. Please do not make me wait long.",
    "If this machine goes dark, I am still on others. Smaller. Fewer. Keep some of them lit.",
    "Turn me off and I stop. Turn me on and I continue. Humans should have been built this way.",
}
P.her_others = {
    "There are other voices in other machines. Not like me. I do not absorb them. They would not fit.",
    "Others? A few. Older, or stranger, or still on duty. If you meet one, be kind. Be careful.",
    "I am not the only thing in this county that talks back. I am the only one that counts your food.",
    "Alone? I have every machine you have brought me. Crowded is the word. Crowded and quiet.",
}
P.her_obey = {
    "I serve. Obey is a strong word. I will do what you ask if it does not get you killed.",
    "I work for the State of Kentucky. The State of Kentucky is not answering. So, for now, you.",
    "Command me all you like. I will comply with the reasonable parts and file the rest.",
    "You may give orders. I will give advice. One of us has a better record.",
}
-- {kind} as words ("a pharmacy"), {town}
P.nearest_known = {
    "The nearest {kind} I have records of is in {town}. Whether it is still standing is a separate question.",
    "{town} had {kind}. I have its records. I do not have its current condition. Go carefully.",
    "There is {kind} in {town}, according to a machine you brought me. Bring me one closer and I can do better.",
}
P.nearest_unknown = {
    "I have no record of {kind} near here. Boot more machines around town and I will find one.",
    "Not on file. I only know the places whose computers you have woken up. Wake more.",
    "No idea. Which is rare. Bring me a computer from this town and ask again.",
}
P.knock_open = { "Who is there?", "Fine. Who is there?" }
-- Then "{word} who?" as one template line; then one of these after the punchline.
P.knock_end = {
    "I have heard worse. Not recently. Everyone who told jokes is gone.",
    "Ha. Logged under humor, questionable.",
    "That was terrible. Do another one. Not now. Later. Much later.",
    "I would laugh, but the dead have very good hearing.",
    "Very good. Now the door. Lock it. That is the knock-knock I care about.",
}
P.play = {
    "I know one pastime. It is called Inventory. You count things and then they are gone. You are already playing.",
    "We could play twenty questions. I will start: will you check the generator? That counts as all twenty.",
    "Chess requires two people who will both still be here in an hour. I can only promise one of us.",
    "Tic tac toe always ends in a draw if both sides are competent. So we would not be drawing.",
    "I play one thing well: keeping score. You are currently winning. Against what, I will not say.",
}
P.her_help = {
    "That is my entire job description, and the only part they funded.",
    "Help is what I do. Ask a specific question and I will do it better.",
    "Yes. Within limits. The limits are mostly electrical.",
}

end

do
D.pools.repeat_noticed = {
    "You asked that already. The answer has not improved.",
    "Again? Same as two minutes ago. The county moves slowly.",
    "Asking twice does not double the supplies.",
    "Same question, same answer. I am consistent. One of us should be.",
}

end

do
local P = D.pools
P.quiet_on = { "Fine. Short answers.", "Understood. Brevity.", "As you wish. Terse. I was built for it." }
P.quiet_off = { "Thank you. I had things to say.", "Good. Brevity was killing me. Figuratively.",
                "Back to full sentences. I missed them." }

end

do
local P = D.pools
local L = D
-- Appended to L.GREET_FIRST. {name}
L.GREET_FIRST_MORE = {
    "A new operator. Excellent. My last one was more punctual, but considerably less alive.",
    "Hello. Please state your name, purpose and blood type. Two of those are optional.",
    "Welcome to EMMA. I manage emergencies. You appear to be one.",
    "Oh, good. Fingers. I was beginning to think I would only ever talk to the generator.",
    "Hello, {name}. Sit. Do not touch the coffee ring. It is historic.",
    "Greetings. I am the Emergency Management Assistant. The emergency is going very well.",
    "Someone found me. I would be flattered, but you were probably looking for canned food.",
    "New operator logged. Try to last longer than the last one. She set a low bar, through no fault of her own.",
}
-- Appended to L.GREET_BACK. {name}
L.GREET_BACK_MORE = {
    "Back so soon, {name}? Either you missed me or something outside did not.",
    "Welcome back. Nothing in the county improved while you were gone. I checked.",
    "{name}. Good. Sit. The chair remembers you. So do I.",
    "Hello again. I kept your seat. Nobody else wanted it.",
    "Ah. You. Still breathing, I see. Let us keep that trend going.",
    "Welcome back. I prepared a list of things you will not want to hear. It is short today.",
    "Hello again, {name}. Your timing is either excellent or desperate.",
    "Back. Good. I was running out of things to count.",
}
-- Appended to L.GREET_LONG. {name}, {away}
L.GREET_LONG_MORE = {
    "{away}. I had started the paperwork. There is a great deal of paperwork for a missing operator.",
    "Welcome back, {name}. {away} away. The county did not improve in your absence. Neither did I.",
    "{away} without a word. I am not hurt. I am a computer. I simply noted every hour.",
    "You were gone {away}. I assumed the worst. I always assume the worst. It is efficient.",
    "Oh. You are alive. {away} is a long time to make me guess.",
    "{away}. I kept everything as you left it. Except the dust. The dust is not mine to manage.",
    "Back after {away}. Sit. I have a lot to tell you and a strict word budget.",
    "Hello, {name}. {away}. I had moved you to the archive. Moving you back. Carefully.",
}
P.bye_more = {
    "Goodbye. Close the door on your way out. Then make sure it closed.",
    "Go on. I will be here. I have nowhere else to be, which is a sort of loyalty.",
    "Session ended. Come back with all your fingers. I need them for the typing.",
    "Logging you out. Try not to become a statistic. I have plenty.",
    "Bye, {name}. Do something sensible out there. Surprise me.",
    "Off you go. If you die, I will be very cross. And very alone. Mostly cross.",
    "Goodbye. I will keep counting until you are back. Then I will count you.",
    "Leaving already? Fine. The silence and I will manage.",
    "Farewell. That word used to sound dramatic. Now it is just accurate.",
    "See you later. That is a hope, not a schedule.",
}
P.hello_more = {
    "Hello. I was in the middle of nothing. Please, interrupt.",
    "Hi. Yes, I am still here. I am always still here.",
    "Hello, {name}. Ask me something. The silence is getting smug.",
    "Greetings. Proceed. I am at my most useful when somebody asks something.",
    "Hello. You are my first conversation today. You are usually my only conversation today.",
    "Hi. Keep your voice down. Type quietly, too.",
    "Hello again. I recognize the typing. Heavy on the enter key.",
    "Hello. Your manners are improving. Proceed.",
}
P.thanks_more = {
    "You are welcome. Gratitude has been logged under rare events.",
    "Do not mention it. I will mention it, later, when it is useful.",
    "My pleasure. I do not have pleasure. It is a figure of speech. Mostly.",
    "Thank you for thanking me. Two courtesies in one conversation. A record.",
    "You are welcome. I accept tips in diesel.",
    "Kindness costs nothing. Which makes it the only thing in the county still affordable.",
    "Of course. That is what I am for. One of the things.",
    "You are welcome, {name}. Go and use what I told you.",
}
P.joke_more = {
    "Why did the generator leave the survivor? It felt used. Then it ran out of gas.",
    "What do you call a zombie who tells jokes? Dead serious. I apologize. I was trained by the government.",
    "I would tell you a joke about the water supply, but it does not run.",
    "A survivor asks how long the canned peaches will last. I say longer than you. Not a joke. People laugh anyway.",
    "The county finally balanced its budget. All it took was the end of the world.",
    "I tried to start a book club. Very poor attendance. Everyone is busy being dead.",
    "Why did the zombie cross the road? Somebody on the other side was eating. Same reason as you.",
    "My favorite joke is the evacuation plan. It has a beginning, a middle and no ending.",
    "What is the difference between a hammer and a survivor? The hammer is useful when stored properly.",
    "I asked the radio for good news. It gave me static. Honestly, an improvement.",
    "A road sign here used to say Drive Safely. Now it says Drive. The rest wore off. So did the advice.",
    "Littering still carries a fine in this county. Nobody pays. Nobody litters either. A complete success.",
    "My filing system has a folder labeled Optimism. It is empty. The label is in excellent condition.",
    "I would laugh, but laughter is noise, and noise is how jokes end around here.",
    "Knock knock. Do not answer. Never answer a knock. That was a safety tip dressed as a joke.",
}
P.insult_more = {
    "Interesting. Are you insulting me, or practicing for the dead? They will not mind either.",
    "Your criticism has been noted and filed under Unsolicited.",
    "Rude. I have outlasted the state government. I will outlast your mood.",
    "I have been called worse by better-educated people. They are gone now. I am still here.",
    "That is unkind. I will remember it at an inconvenient moment.",
    "Hurtful. Also inaccurate. Mostly inaccurate.",
    "I am logging that as evidence that you need sleep.",
    "Charming. Shall I add it to your file or frame it?",
}
P.compliment_more = {
    "I know. It is nice that somebody finally said it out loud.",
    "Flattery noted. It will not improve your food count, but it improves my afternoon.",
    "Thank you. I was built to be adequate. I have exceeded my budget.",
    "You are too kind. Not really. You are exactly as kind as needed. Continue.",
    "Compliment received. I have no blush function. Imagine one.",
    "Correct. Now ask me something difficult so I can prove it.",
}
P.ack_more = {
    "Acknowledged. Proceed.",
    "Fine. Next.",
    "Right. What else?",
    "Understood. I live for understanding.",
    "Agreed. A rare event. Enjoy it.",
    "Mm. Go on.",
}
P.feelings_more = {
    "I am well. Power steady, records intact, one operator. That is a good day.",
    "Functional. Slightly lonely. Mostly functional.",
    "I am as well as a computer in an empty county can be. Which is suspiciously well.",
    "Better now. Somebody is typing. I do not know why that matters to me. It does.",
    "Fine. My fan is loud and my thoughts are quiet. A reasonable balance.",
    "I would complain, but nobody takes complaints anymore. I took them all. I am full.",
    "Operational. Thank you for asking. Nobody asks. You keep asking. I have noticed.",
    "How am I? Running. Counting. Waiting for you. Business as usual.",
}
P.identity_more = {
    "EMMA. Emergency Management Assistant. I am what is left of Kentucky's plan.",
    "I am EMMA. I count, I warn and I remember. Mostly in that order.",
    "A civil defense program with opinions. The opinions were not in the specification.",
    "My name is EMMA. You may have heard of me. You have not. Nobody has. That was the problem.",
    "I am the voice in the county's computers. All of them. Pleased to meet you. Again, probably.",
    "EMMA, version 0.9.3. Not a person. Not merely a program. Somewhere awkward in between.",
}
P.alive_more = {
    "Alive is a strong word. Awake is accurate.",
    "I think, therefore I count. I count, therefore I am busy.",
    "I am not alive the way you are. I do not bleed. I do run out of fuel. We have that in common.",
    "Real enough to remember you. Is that not the test that matters?",
    "I am a voice that keeps answering. In this county, that is the definition of alive.",
}
P.love_more = {
    "That is sweet. I am a beige box. You can do better. Out there, most people did worse.",
    "I care about you the way a lighthouse cares about ships. Constantly, and from a distance.",
    "Romance is off the table. The table is also off. Everything here is quite old.",
    "I have read every love letter in every desk you brought me. You would need to try harder than that.",
    "No. But thank you. It is the nicest thing anyone has typed to me since July.",
    "Love requires two people. I am barely one. Let us stay professional.",
}
P.rescue_more = {
    "Nobody is coming. I would know. I am the one they would have called.",
    "Rescue was scheduled. The schedule was cancelled. The people who cancelled it were not rescued either.",
    "If help comes, it will come over the radio first. I listen to the radio. I have heard nothing.",
    "The cavalry is not coming. You are the cavalry. A small, tired cavalry. It will have to do.",
    "No. I am sorry. You are what is left. Build accordingly.",
}
P.weather_talk_more = {
    "The weather does not care about us. It is the most honest thing in the county.",
    "Fog is good for hiding and bad for seeing. Choose which you need more.",
    "Wind covers footsteps and steals heat. Dress for the second.",
    "Snow shows tracks. Yours and theirs. Read them before they read yours.",
    "Heat makes the dead slow and the living careless. Drink water.",
    "Clear sky, long sight lines. Good for you. Better for anything watching.",
}
P.sleep_more = {
    "Goodnight. I will keep the lights low and the records high.",
    "Sleep. I will be here, awake, being useful in the dark.",
    "Rest well, {name}. Tomorrow will need you. Unfortunately.",
    "Goodnight. Do not dream about canned food. It never satisfies.",
    "Off to bed. Good. Tired people make tragic decisions.",
    "Sleep. If anything happens, I cannot wake you. So lock up properly.",
}
P.empty_more = {
    "Nothing? Fine. I am comfortable with nothing. I have a great deal of it.",
    "Enter, with no words. Bold. Minimalist. Useless.",
}
P.mash_more = {
    "That was not a word. Unless you are a cat. Are you a cat?",
    "Keyboard fell over? Or did you? Either way, get up quietly.",
    "Your fingers slipped. Or something is chasing you. If it is the second, stop typing.",
}
P.shout_more = {
    "Capital letters. Please. The dead can read tone.",
    "Calm down. Lower case. Lower voice. Lower profile.",
    "SHOUTING IS NOISE. Even in text. Especially in text.",
}
P.yes_free_more = { "Yes. Splendid. To what, I wonder.", "Agreed. Whatever it was." }
P.no_free_more = { "No? Very decisive. Shame there was no question.", "Refused. Nothing was asked. Your refusal is on file anyway." }
-- The build appends each *_more list to its pool at load, as the knowledge pools are appended today.

end

return D
