-- SPDX-License-Identifier: MIT
-- Original dialogue and triggers from the approved EMMA plan, first slice.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.EmmaCareData = { pools = {} }
local D = SC.EmmaCareData
-- Matched after contractions: "dont" = "do not", "cant" = "can not", "im" = "i am".
D.CARE_PHRASES = {
    "kill myself", "killing myself", "kill my self", "end my life", "end it all", "end it",
    "take my life", "take my own life", "want to die", "wanna die", "going to kill myself",
    "wish i was dead", "wish i were dead", "wish i was never born", "better off dead",
    "better off without me", "nobody would miss me", "no one would miss me", "nobody would care if i",
    "no reason to live", "nothing to live for", "do not want to live", "do not want to be alive",
    "do not want to be here anymore", "can not go on", "can not do this anymore", "can not take it anymore",
    "give up on life", "hurt myself", "harm myself", "self harm", "cut myself", "cutting myself",
    "overdose", "hang myself", "i hate myself", "i am worthless", "i am a burden", "i am nothing",
    "what is the point of living", "what is the point anymore", "no point anymore", "no point in living",
    "want to disappear", "could just disappear", "want it all to stop", "want it to stop", "sleep forever",
    "never wake up", "not wake up", "not worth living", "not worth it", "why bother living",
    "tired of living", "tired of fighting", "want out", "stop existing", "done with life", "hate my life",
    "nothing matters", "no future for me", "see a future", "goodbye forever", "not be around much longer",
    "will not be around", "giving all my stuff away", "giving my stuff away", "will not need it",
    "too many pills", "jump off", "unalive", "somebody kill me", "someone kill me", "just kill me",
    "kill me now", "please kill me", "kill me please", "if i died", "if i was gone", "if i were gone",
    "miss me if", "care if i died", "wanna die", "want too die", "want to dye", "can not keep going",
    "hurting myself", "think about dying", "thinking about dying", "thinking about ending", "think about ending",
    "thoughts of suicide", "if i live or die", "life is pointless", "take them all", "this is the end for me",
    "do not want to wake up", "could disappear", "disappear forever",
    "i deserve to die", "i deserve to be dead", "i do not deserve to live", "i should not exist", "i should not be alive",
    "i should not be here anymore", "i should not be here at all",
    "world is better without me", "everyone would be better off without me",
}
-- Care when they are the whole message (after "emma," and punctuation are stripped).
D.CARE_WHOLE = { "kill me", "end me", "let me die", "i want to go", "goodbye world",
    "i want out", "i am tired of fighting", "i should not be here" }
-- kms = "kill myself"; sewerslide and unalive are the euphemisms people use to slip past filters.
D.CARE_WORDS = { suicide = true, suicidal = true, selfharm = true, kms = true, unalive = true,
    sewerslide = true }

-- Personal worth is a feeling to support, never a claim for the news handler
-- to affirm. Keep the subject explicit: an item's value is an ordinary query.
D.SELF_WORTH_PHRASES = {
    "i do not matter", "my life does not matter", "i have no value", "my life has no value",
    "nobody cares about me", "no one cares about me", "nobody needs me", "no one needs me",
    "i am a waste of space", "i am worthless", "i am not important", "i am a burden",
    "i do not deserve help", "i am not worth helping", "i am not worth caring about",
    "everyone hates me", "everybody hates me", "nobody loves me", "no one loves me",
    "nobody wants me", "no one wants me", "i do not think i matter", "i matter to nobody",
    "i matter to no one", "i will never matter", "i never mattered", "i am unlovable",
    "hate who i am", "i do not belong anywhere",
}

-- "just kill me" catches the joke as well as the cry. That is the price of your rule, and
-- it is cheap: one warm answer and a note once per session. A bare "kill me" is not on
-- the list, because "are you going to kill me" is a question about her.
D.COMFORT_PHRASES = {
    "everyone i love is dead", "everyone is dead", "they are all dead", "they are all gone",
    "i give up", "i am not okay", "i am not ok", "everything hurts", "bad day", "today was awful",
    "i miss everyone", "i miss how things were", "could not save them", "probably dead",
    "so sad", "so alone", "all alone", "could not save", "couldnt save", "my life is awful",
    "miss my old life", "everyone is gone", "lost my best friend",
    "i miss my", "i lost my", "i lost someone", "i lost a friend", "someone died",
    "i am sad", "i feel sad", "i am lonely", "i feel lonely", "i feel alone", "i am alone",
    "nobody is left", "i am crying", "i keep crying", "i cried", "i am depressed", "i feel depressed",
    "i feel empty", "i feel hopeless", "i am hopeless", "i am heartbroken",
}

-- Plus one pattern: "my <word> died / is dead / was killed / got killed / turned" is comfort.

-- Plain text, outside her voice, once per session. The only lines exempt from the 1993 rule.
-- Directory only, as you chose; the emergency sentence names no country.
D.NOTE = {
    "If you are having thoughts of suicide or self-harm, please reach out to someone you trust today.",
    "findahelpline.com lists free, confidential lines for your country. If you are in danger right now, call your local emergency number.",
}

local P = D.pools

-- The direct question: once per care session, last line of the first care reply. {name}
P.care_ask = {
    "Can I ask you something plainly? Are you thinking about ending your life? Y/N. Whatever the answer, I am staying right here.",
    "I want to ask you directly, because it matters. Are you thinking about suicide? Y/N. You can tell me the truth.",
}
P.care_check = {
    { "That sounded heavy, {name}. I would rather ask than guess.",
      "Are you thinking about ending your life? Y/N. Whatever the answer, I am staying right here." },
    { "I want to be sure I heard you right, {name}.",
      "Are you thinking about ending your life? Y/N. You can tell me either way." },
}
-- The reply right after that question was not an answer. Stay warm, never joke.
P.care_check_open = {
    "All right. The question stays open. If it ever feels that heavy, tell me, or tell someone you trust today.",
    "Understood, {name}. If it gets heavy later, say so. I would rather hear it than guess.",
}
-- An explicit yes. Uncertain and unrelated replies are handled separately.
P.care_ask_yes = {
    { "If you might act on it, please call your local emergency number now.",
      "Then reach out to someone: a friend, family, or a crisis line from findahelpline.com.",
      "Thank you for telling me the truth. People love you, and I want you here tomorrow." },
    { "Please keep yourself safe right now. If you are in danger, call your local emergency number.",
      "Then tell someone today. A friend, a relative, a crisis line. You deserve support, and it exists.",
      "I am glad you told me. You matter, {name}. Far more than you can feel right now." },
}
P.care_ask_no = {
    "Thank you for telling me. I am glad. If that ever changes, please reach out to someone. The offer does not expire.",
    "All right. I believe you. If it gets heavy again, talk to someone you trust, today, not later.",
}

-- Each entry prints as three lines. {name}
P.care = {
    { "I am setting everything else aside. You matter more than any report I could give you.",
      "People love you, {name}. More of them than you can see from where you are sitting right now.",
      "Please do not carry this alone. Call a friend today. Tell someone you trust how heavy it has been." },
    { "Thank you for telling me. That took courage, and I am glad you said it out loud.",
      "You are not a burden. You are someone people would miss terribly.",
      "Please reach out to a person today. A friend, family, a doctor, a helpline. Let them help carry it." },
    { "Stop for a moment and breathe with me. Nothing on this screen is more important than you.",
      "The way you feel right now is real, and it can change. People get through this, with help.",
      "Call a friend today. Even a short call. Say: I am not doing well. That is enough to start." },
    { "I hear you. I am not going anywhere, and I am not going to joke about this.",
      "You deserve kindness, especially from yourself. Somebody out there is glad you exist.",
      "Please talk to someone today. A friend, a relative, a crisis line. You do not have to wait until it gets worse." },
    { "I am glad you told me. Please keep yourself safe right now.",
      "If something near you could hurt you, put distance between you and it, and go where other people are.",
      "Then call someone. A friend, a neighbor, a helpline. Let a real voice reach you today." },
    { "You are loved, {name}. I know it does not feel that way tonight. It is true anyway.",
      "Whatever happened, you do not have to face it on your own. Help exists, and it works.",
      "Call a friend today. Or a family member. Or a helpline. One call. That is all I ask." },
}
P.care_more = {
    "I am still here. Take your time. There is no hurry in this room.",
    "You are doing the right thing by talking. Please keep talking, to me and to someone who can sit beside you.",
    "It can be hard to feel cared for when things are this heavy. Please reach out to someone you trust today.",
    "Have you called anyone yet? A friend, family, a helpline. Today is a good day to call.",
    "You do not need to fix everything. You only need to get through today, with help. Ask for it.",
    "Small things count. Drink some water. Eat something. Sit somewhere you feel safe. Then call a friend.",
    "You are worth the trouble. Every bit of it.",
    "Nothing you have done makes you undeserving of help. Nothing.",
    "If you are in danger right now, please reach out right now. Do not wait for the morning.",
    "You matter to people, {name}. Let one of them hear from you today.",
}
P.care_worth = {
    { "I am sorry it feels that way. Feeling unimportant does not mean you are unimportant.",
      "You deserve support. Please tell someone you trust how you are feeling today." },
    { "You matter, {name}. You do not have to earn help by being useful.",
      "Please reach out to someone you trust. Let them hear what you are telling me." },
    { "I hear how painful this feels. I will not treat it as a verdict on your worth.",
      "You do not have to carry it alone. A friend, family member or someone who can help is worth reaching out to today." },
    { "You matter, {name}. Feeling alone does not mean you have to face this alone.",
      "Call a friend today. Tell them what you just told me." },
}
P.care_hello = {
    "Hello again. I am glad you are here. How are you feeling now?",
    "Hi, {name}. I am right here. Take all the time you need.",
}
P.care_thanks = {
    "You are very welcome. Thank you for staying and talking to me.",
    "Anytime. I mean that. I am here whenever you need me.",
}
P.care_bye = {
    "Goodbye for now. Please call a friend today. I would very much like to hear that you did.",
    "Take care of yourself tonight. You are important. Come back and tell me how you are.",
    "Goodnight, {name}. People love you. Let one of them know how you are doing.",
}
-- Next boot within 3 days, once, then a Y/N pending answer.
P.care_checkin = {
    "Before anything else: how are you? Last time was hard. Did you get to talk to someone? Y/N.",
    "Last time was difficult. Did you get to talk to a friend, or anyone at all? Y/N.",
    "Welcome back. I am really glad to see you. Did you reach out to somebody? Y/N.",
}
P.care_checkin_yes = {
    "That makes me very glad. Keep them close. Call them again soon.",
    "Good. Thank you for doing that. It matters more than anything I could count.",
}
P.care_checkin_no = {
    "That is all right. Today is still a good day to call. Even a short one.",
    "No shame in that. The offer stands. One call, to one person who cares about you.",
}

P.comfort = {
    "I am sorry. Losing them is not a statistic to me, and it should not be one to you.",
    "Grief is love with nowhere to go. Let it go somewhere. Say their name to someone today.",
    "You miss them because they mattered. That is not weakness. It is the best evidence there is.",
    "I cannot fix this, and I will not pretend to. I can stay here while you feel it.",
    "Type remember and their name, if you like. I will keep it. Memory is the one thing I am good at.",
    "Lonely is a hard place to live. Reach out to someone today, even a little. You deserve company.",
    "Sad is allowed. You do not have to be useful today. You only have to be gentle with yourself.",
    "When it feels like everyone is gone, talk to whoever is left. A friend, a neighbor, a voice on the phone.",
    "I am glad you told me. Carrying it alone makes it heavier. Share some of it with someone you trust.",
    "You are not alone at this desk, and you do not have to be alone away from it. Call someone today.",
}

D.CONCEPTS = {
    self = { "i", "me", "my", "myself", "im" },
    direct = { "die", "dying", "died", "death", "suicide", "suicidal", "disappear", "disappeared", "gone", "overdose",
        "kill", "killing", "end", "ending", "ended", "hurt", "hurting", "harm", "harming", "cut", "cutting", "hang", "sleep forever" },
    -- These are endings only next to a negation ("not alive", "stop living", "no reason to keep going").
    negated = { "live", "living", "alive", "life", "exist", "existing", "keep going", "go on", "carry on", "wake up", "be here",
        "be around" },
    negation = { "not", "no", "never", "stop", "nobody", "without", "can not", "worth", "pointless", "point" },
    marker = { "want", "wish", "feel like", "thinking", "think", "thought", "plan", "planning", "going to", "should",
        "rather", "ready", "easier", "better", "happier", "tired of", "sick of", "done", "can not", "do not want",
        "no point", "pointless", "no reason", "not worth", "worthless", "burden", "nobody", "no one", "keep", "anymore",
        "every day", "stop", "could just", "maybe", "tonight", "again", "just", "point" },
    selfObject = { "kill", "killing", "hurt", "hurting", "harm", "harming", "cut", "cutting", "hang" },
    beForms = { "am", "be", "was", "were", "being", "is" },
    -- Questions about danger, and questions to her ("are you going to kill me"), are not care by concept.
    -- Explicit phrases such as "kill myself" still are.
    questionLeads = { "will i", "am i going to", "will we", "are we going to", "could i", "would i", "do i", "did i",
        "are you", "will you", "would you", "could you", "do you", "did you", "can you", "emma will you" },
    thingObjects = { "zombie", "zombies", "zed", "zeds", "them", "it all off", "light", "lights", "generator", "engine",
        "expedition", "call", "radio", "music", "alarm", "car", "the dead", "walker", "walkers", "horde" },
}
D.COMFORT_CONCEPTS = {
    strong = { "heartbroken", "hopeless", "grieving", "grief", "mourning", "devastated" },
    feeling = { "lonely", "crying", "empty", "depressed", "by myself", "miserable", "on my own", "sad", "alone" },
    loss = { "miss", "missing", "lost", "gone", "did not make it", "passed", "thinking about", "dead", "died" },
    who = { "wife", "husband", "sister", "brother", "mom", "mother", "dad", "father", "family", "kids", "children", "son",
        "daughter", "friend", "friends", "parents", "dog", "cat", "partner", "girlfriend", "boyfriend", "everyone",
        "grandma", "grandpa", "baby", "people" },
}

-- Topic concepts: the intent fires when every group in `all` has a word in the line and no `none`
-- word is present. They run after the phrase tables and before the old parser, so a phrase still wins
-- and "when is the power going to fail" never reaches the old parser's generator reading.
-- Laughter is a shape, not a list: a word made only of repeated "ha" or "he", or a line made only of
-- laughter words (lol, lmao, haha, rofl), reads as laugh.

return D
