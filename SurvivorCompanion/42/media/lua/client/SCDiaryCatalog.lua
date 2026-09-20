-- SPDX-License-Identifier: MIT
--
-- Authored private diary passages. Every packet is a complete, coherent
-- passage family admitted only by explicit evidence keys that the trusted
-- SCDiary adapter proves. `asserts` records, for review, what the prose claims
-- as fact; everything else in a passage is the writer's own private feeling.
--
-- Evidence contract (all proven by SCDiary, never guessed here):
--   recruitment.committed            the writer was recruited by the player
--   time.same_day / time.night       calendar day of occurrence == writing day;
--                                    writing hour is late evening or night
--   time.callback_due                the referenced anchor is old enough
--   player.he / player.she           the historical player's visible sex
--   subject.he / subject.she         the same for the named other person
--   relationship.guarded|warming|close   writer's current tier toward the player
--   relationship.trusted_sustained   tier trusted or higher held >= a game day
--   relationship.recent_major_breach a broken promise in the last three days
--   writer.shaken                    writer's current mood is shaken or uneasy
--   writer.still_with_player         the writer is still recruited
--   wound.<kind>                     a new wound of that kind appeared on the
--                                    writer's own body (scratch, laceration,
--                                    deep, burn, fracture, bullet, glass, bite)
--   wound.multiple                   more than one new wound appeared together
--   wound.part_leg                   the wound is on a leg, foot or groin
--   wound.dressed / wound.healed     that part is bandaged / no longer wounded now
--   wound.all_healed                 the writer has no wound left at all
--   symptoms.none|early|mid|late     perceived (apparent) Knox fever tier now
--   infection.bite_known             the writer has seen a bite on their body
--   infection.scratch_known          a recent scratch or cut, and no bite
--   infection.cause_unknown          symptoms with neither
--   bite.hidden|confessed|self_exile_planned   the writer's own crisis choice
--   crisis.outcome.<outcome>         the group's decision about the writer
--   crisis.other_bitten_known        the writer confirmed another's bite
--   crisis.learned.<path>            how: witnessed_bite, confession,
--                                    visible_symptoms, medical_exam
--   stance.<stance>                  the writer's own stance in that crisis
--   death.known_to_writer            the writer grieves this death
--   death.witnessed                  the writer was close by when it happened
--   death.subject_close              the writer knew the subject well
--   care.player_bandaged_writer      a verified bandage by the player
--   care.companion_bandaged_writer   a verified bandage by another survivor
--   care.writer_bandaged_self        a verified self bandage
--   care.used_torn_clothing          that dressing was torn from clothing
--   care.writer_bandaged_player|companion   the writer verified-bandaged them
--   danger.escape_with_player        the recorded shared escape
--   interior.dread                   native environmental stress rose for the
--                                    writer while the nearby player stayed calm
--   interior.panic                  native panic crossed an onset/recovery edge
--   interior.nicotine               a smoker had native nicotine withdrawal
--   anchor.<key>.committed           a committed page holds that anchor quote
--   anchor.<key>.on_first_page       that page is the diary's first entry
--   anchor.<key>.mentions_better_idea
--   background.fear.<code>           fixed personal canon

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.DiaryCatalog = SC.DiaryCatalog or {}
local Catalog = SC.DiaryCatalog

Catalog.VERSION = 1

Catalog.VOICES = {
    guarded_practical = { register = "plain", openness = "low", humor = "dry",
        rhythm = "short_mixed", coping = "keeping_busy" },
    warm_candid = { register = "plain", openness = "high", humor = "gentle",
        rhythm = "flowing", coping = "looking_after_others" },
    blunt_brave = { register = "clipped", openness = "low", humor = "gallows",
        rhythm = "fragments", coping = "pushing_through" },
    wry_watchful = { register = "plain", openness = "medium", humor = "wry",
        rhythm = "lists_and_asides", coping = "planning" },
}

-- Personality weights a persisted voice choice; it never dictates it.
Catalog.ARCHETYPE_VOICE_WEIGHTS = {
    practical = { guarded_practical = 6, wry_watchful = 2, blunt_brave = 1, warm_candid = 1 },
    cautious = { wry_watchful = 6, guarded_practical = 3, warm_candid = 1 },
    caring = { warm_candid = 6, guarded_practical = 2, wry_watchful = 2 },
    brave = { blunt_brave = 6, guarded_practical = 2, warm_candid = 1, wry_watchful = 1 },
}

local ALL = { guarded_practical = 4, warm_candid = 4, blunt_brave = 4, wry_watchful = 4 }

local packets = {
    ----------------------------------------------------------------- joining
    {
        id = "join.guarded", scene = "joined", ideaId = "provisional_stay",
        shape = "guarded_note", voiceWeights = { guarded_practical = 8, wry_watchful = 2 },
        requires = { "recruitment.committed" },
        asserts = "The writer joined the player.",
        variants = {
            { id = "a", requires = { "time.same_day", "player.he" },
                text = "Joined {player} today. Don't know him well enough to say whether that was sensible.\n\nI'll stay until I have a better idea.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I'll stay until I have a better idea." },
            { id = "b", requires = { "time.same_day", "player.she" },
                text = "Joined {player} today. Don't know her well enough to say whether that was sensible.\n\nI'll stay until I have a better idea.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I'll stay until I have a better idea." },
            { id = "c",
                text = "Joined {player}. Still not sure about this.\n\nFor now, this is better than being on my own.",
                anchorKey = "first_reason_to_stay", anchorQuote = "For now, this is better than being on my own." },
        },
    },
    {
        id = "join.hopeful", scene = "joined", ideaId = "wanting_it_to_work",
        shape = "private_admission", voiceWeights = { warm_candid = 8, blunt_brave = 1 },
        requires = { "recruitment.committed" },
        asserts = "The player asked the writer to come along, and the writer agreed.",
        variants = {
            { id = "a", requires = { "time.same_day" },
                text = "{player} asked me to come along today, and I said yes before I could talk myself out of it.\n\nI want this to be the right decision. I'm writing that down so I remember I wanted it.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I want this to be the right decision." },
            { id = "b",
                text = "New company. {player}, and whatever comes with {player}.\n\nIt's been a long time since anyone asked me to come along. I'll try to be worth it.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I'll try to be worth it." },
            { id = "c", requires = { "background.fear.being_alone" },
                text = "Went with {player}.\n\nI was more afraid of being on my own than of a stranger. I still am, a little. I'll try to be worth it.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I'll try to be worth it." },
        },
    },
    {
        id = "join.blunt", scene = "joined", ideaId = "trial_partnership",
        shape = "terse_note", voiceWeights = { blunt_brave = 8, guarded_practical = 1 },
        requires = { "recruitment.committed" },
        asserts = "The writer joined the player.",
        variants = {
            { id = "a", requires = { "time.same_day" },
                text = "Going with {player} from today. Two can watch each other's backs.\n\nIf it doesn't work out, I can always leave.",
                anchorKey = "first_reason_to_stay", anchorQuote = "If it doesn't work out, I can always leave." },
            { id = "b",
                text = "Signed on with {player}. No speeches.\n\nIf it doesn't work out, I can always leave.",
                anchorKey = "first_reason_to_stay", anchorQuote = "If it doesn't work out, I can always leave." },
        },
    },
    {
        id = "join.watchful", scene = "joined", ideaId = "cautious_inventory",
        shape = "list_and_aside", voiceWeights = { wry_watchful = 8, guarded_practical = 2 },
        requires = { "recruitment.committed" },
        asserts = "The writer joined the player.",
        variants = {
            { id = "a", requires = { "time.same_day" },
                text = "Joined up with {player} today.\n\nThings I know about {player}: not much. Things I know about being alone out here: enough.\n\nI'll stay for now, and keep one eye on the door.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I'll stay for now, and keep one eye on the door." },
            { id = "b",
                text = "Travelling with {player} now.\n\nReasons to stay: safer in pairs. Reasons to go: haven't found one yet. I'll stay for now, and keep one eye on the door.",
                anchorKey = "first_reason_to_stay", anchorQuote = "I'll stay for now, and keep one eye on the door." },
        },
    },

    ------------------------------------------------------ trust (callback)
    {
        id = "trust.guarded", scene = "trust", ideaId = "choosing_to_stay",
        shape = "quote_and_correction", voiceWeights = { guarded_practical = 8 },
        requires = { "anchor.first_reason_to_stay.committed", "relationship.trusted_sustained",
            "time.callback_due", "writer.still_with_player" },
        forbids = { "relationship.recent_major_breach" },
        asserts = "An earlier page really contains the quoted line.",
        variants = {
            { id = "a", requires = { "anchor.first_reason_to_stay.mentions_better_idea",
                "anchor.first_reason_to_stay.on_first_page" },
                text = "First page says, '{earlier_quote}'\n\nApparently I have run out of better ideas.\n\nNo. That's not it. I want to stay." },
            { id = "b",
                text = "Earlier I wrote, '{earlier_quote}'\n\nI meant it then. I want to stay now, and not just because the other options are worse." },
        },
    },
    {
        id = "trust.warm", scene = "trust", ideaId = "belonging",
        shape = "quote_and_reflection", voiceWeights = { warm_candid = 8 },
        requires = { "anchor.first_reason_to_stay.committed", "relationship.trusted_sustained",
            "time.callback_due", "writer.still_with_player" },
        forbids = { "relationship.recent_major_breach" },
        asserts = "An earlier page really contains the quoted line.",
        variants = {
            { id = "a", requires = { "anchor.first_reason_to_stay.on_first_page" },
                text = "The first page says, '{earlier_quote}'\n\nI don't think I have to try so hard any more. I think I just belong here now." },
            { id = "b",
                text = "I wrote '{earlier_quote}' back when I barely knew {player}.\n\nIt sounds like somebody else wrote it. I'm glad it was me." },
        },
    },
    {
        id = "trust.blunt", scene = "trust", ideaId = "never_left",
        shape = "quote_and_shrug", voiceWeights = { blunt_brave = 8 },
        requires = { "anchor.first_reason_to_stay.committed", "relationship.trusted_sustained",
            "time.callback_due", "writer.still_with_player" },
        forbids = { "relationship.recent_major_breach" },
        asserts = "An earlier page really contains the quoted line; the writer is still with the player.",
        variants = {
            { id = "a",
                text = "Earlier I wrote, '{earlier_quote}'\n\nNever did leave. Not planning to." },
            { id = "b",
                text = "Looked back at what I wrote at the start. '{earlier_quote}'\n\nFunny. {player} grew on me." },
        },
    },
    {
        id = "trust.watchful", scene = "trust", ideaId = "stopped_counting_exits",
        shape = "quote_and_aside", voiceWeights = { wry_watchful = 8 },
        requires = { "anchor.first_reason_to_stay.committed", "relationship.trusted_sustained",
            "time.callback_due", "writer.still_with_player" },
        forbids = { "relationship.recent_major_breach" },
        asserts = "An earlier page really contains the quoted line.",
        variants = {
            { id = "a",
                text = "Earlier I wrote, '{earlier_quote}'\n\nStill watching the door. Mostly out of habit now." },
            { id = "b", requires = { "anchor.first_reason_to_stay.on_first_page" },
                text = "First page: '{earlier_quote}'\n\nI've stopped keeping a list of reasons to go. I didn't notice when." },
        },
    },

    ------------------------------------------------------------------ wounds
    {
        id = "wound.scratch_worry", scene = "wound", ideaId = "scratch_worry",
        shape = "private_admission",
        voiceWeights = { wry_watchful = 8, guarded_practical = 6, warm_candid = 4, blunt_brave = 2 },
        requires = { "wound.scratch", "symptoms.none" }, forbids = { "infection.bite_known" },
        asserts = "The writer has a new scratch on the named body part.",
        variants = {
            { id = "a", requires = { "time.same_day" },
                text = "Got scratched on the {part} today. It's small.\n\nI keep looking at it anyway.",
                anchorKey = "scratch_worry", anchorQuote = "I keep looking at it anyway." },
            { id = "b",
                text = "A scratch on my {part}. Everyone knows what people say about scratches.\n\nIt's probably nothing. I'm going to keep saying that until I believe it.",
                anchorKey = "scratch_worry", anchorQuote = "It's probably nothing." },
        },
    },
    {
        id = "wound.scratch_shrug", scene = "wound", ideaId = "scratch_bravado",
        shape = "bare_note", voiceWeights = { blunt_brave = 8, guarded_practical = 3 },
        requires = { "wound.scratch", "symptoms.none" }, forbids = { "infection.bite_known" },
        asserts = "The writer has a new scratch on the named body part.",
        variants = {
            { id = "a",
                text = "Scratch on the {part}. Not worth the ink.\n\nWriting it down anyway, which probably says something." },
            { id = "b", requires = { "time.same_day", "time.night" },
                text = "Took a scratch on my {part} today.\n\nNot going to spend the night staring at it. Probably." },
        },
    },
    {
        id = "wound.laceration", scene = "wound", ideaId = "cut_slows_me",
        shape = "mundane_note", voiceWeights = ALL,
        requires = { "wound.laceration" },
        asserts = "The writer has a new cut on the named body part.",
        variants = {
            { id = "a",
                text = "Got cut on the {part}. Deeper than I'd like.\n\nEverything takes twice as long with it." },
            { id = "b", requires = { "wound.dressed" },
                text = "The cut on my {part} is wrapped now. It throbs while I write, which is inconvenient, because I'm writing." },
            { id = "c", requires = { "symptoms.none" }, forbids = { "infection.bite_known", "wound.dressed" },
                text = "Got cut on the {part}. It's the kind of cut people worry about now.\n\nI'm worrying about it.",
                anchorKey = "scratch_worry", anchorQuote = "I'm worrying about it." },
        },
    },
    {
        id = "wound.deep", scene = "wound", ideaId = "deep_wound",
        shape = "shaken_note", voiceWeights = ALL,
        requires = { "wound.deep" },
        asserts = "The writer has a new deep wound on the named body part.",
        variants = {
            { id = "a",
                text = "Deep wound in the {part}.\n\nThere's more inside a person than I ever wanted to see." },
            { id = "b", requires = { "wound.dressed", "time.night" },
                text = "It's bandaged. My {part} still doesn't feel like mine.\n\nIf I sleep tonight it will be out of spite." },
        },
    },
    {
        id = "wound.burn", scene = "wound", ideaId = "burned",
        shape = "mundane_note", voiceWeights = ALL,
        requires = { "wound.burn" },
        asserts = "The writer has a new burn on the named body part.",
        variants = {
            { id = "a",
                text = "Burned my {part}. It hurts more than it looks.\n\nFire used to mean dinner." },
            { id = "b", requires = { "background.fear.fire" },
                text = "Burned my {part}. Of all the things.\n\nI've been afraid of fire my whole life. Turns out that was reasonable." },
        },
    },
    {
        id = "wound.fracture", scene = "wound", ideaId = "broken_bone",
        shape = "frustrated_note", voiceWeights = ALL,
        requires = { "wound.fracture" },
        asserts = "A bone in the named body part is fractured.",
        variants = {
            { id = "a",
                text = "My {part} is broken. Everything I do now has to be planned around it.\n\nI hate being slow." },
            { id = "b", requires = { "wound.part_leg" },
                text = "Broken {part}. Walking has turned into a negotiation, and I'm losing." },
        },
    },
    {
        id = "wound.bullet", scene = "wound", ideaId = "shot",
        shape = "bare_note", voiceWeights = ALL,
        requires = { "wound.bullet" },
        asserts = "A bullet is lodged in the named body part.",
        variants = {
            { id = "a", text = "There is a bullet in my {part}.\n\nThe dead don't carry guns. I keep coming back to that." },
            { id = "b", text = "Shot. The {part}.\n\nOf everything out here, it was a person." },
        },
    },
    {
        id = "wound.glass", scene = "wound", ideaId = "glass",
        shape = "bare_note", voiceWeights = ALL,
        requires = { "wound.glass" },
        asserts = "Glass is lodged in the named body part.",
        variants = {
            { id = "a", text = "Glass in my {part}.\n\nEverything out here has edges now." },
            { id = "b", text = "Glass in my {part}.\n\nI'll be finding bits of it for days." },
        },
    },
    {
        id = "wound.multiple", scene = "wound", ideaId = "hurt_all_over",
        shape = "shaken_note", voiceWeights = ALL,
        requires = { "wound.multiple", "time.same_day" },
        asserts = "The writer received more than one wound on the same day.",
        variants = {
            { id = "a", text = "Hurt in more than one place today.\n\nI'm writing this so there's a record that I was well enough to write." },
            { id = "b", requires = { "writer.shaken" },
                text = "Bad day. More than one new wound.\n\nMy hands have mostly stopped shaking. Mostly." },
        },
    },

    ------------------------------------------------------------------- bites
    {
        id = "bite.hidden", scene = "bite", ideaId = "hiding_bite",
        shape = "confession_to_page",
        voiceWeights = { wry_watchful = 8, guarded_practical = 6, blunt_brave = 4, warm_candid = 3 },
        requires = { "wound.bite", "bite.hidden" },
        asserts = "The writer has a bite on the named part and has chosen not to tell anyone.",
        variants = {
            { id = "a",
                text = "I've been bitten. The {part}.\n\nI haven't told anyone. I'm telling this instead, because paper can't look at me the way they would.",
                anchorKey = "bite_secret", anchorQuote = "I haven't told anyone." },
            { id = "b",
                text = "Bitten on the {part}.\n\n{player} doesn't know. I keep deciding to say it, and then not saying it.",
                anchorKey = "bite_secret", anchorQuote = "I keep deciding to say it, and then not saying it." },
        },
    },
    {
        id = "bite.told", scene = "bite", ideaId = "bite_told",
        shape = "private_admission",
        voiceWeights = { warm_candid = 8, guarded_practical = 6, blunt_brave = 6, wry_watchful = 4 },
        requires = { "wound.bite", "bite.confessed" },
        asserts = "The writer has a bite on the named part and has told the group.",
        variants = {
            { id = "a",
                text = "I was bitten on the {part}. I told them.\n\nSaying it out loud made it true in a way the bite didn't." },
            { id = "b", requires = { "relationship.close" },
                text = "Bitten. {player} knows. I couldn't have kept it from {player} anyway.\n\nWhatever happens now, at least I don't have to pretend." },
            { id = "c", requires = { "anchor.bite_secret.committed" },
                text = "Earlier I wrote, '{earlier_quote}'\n\nThey know now. It's worse and it's better." },
        },
    },
    {
        id = "bite.leaving", scene = "bite", ideaId = "leaving_before_asked",
        shape = "decision_note",
        voiceWeights = { blunt_brave = 8, guarded_practical = 6, wry_watchful = 6, warm_candid = 4 },
        requires = { "wound.bite", "bite.self_exile_planned" },
        asserts = "The writer has a bite on the named part and intends to leave.",
        variants = {
            { id = "a",
                text = "The {part}. A bite.\n\nI know how this goes. I'd rather walk away than make someone else decide for me." },
            { id = "b",
                text = "Bitten.\n\nI'm not going to make {player} look at me and choose. I'll go before it comes to that." },
        },
    },
    {
        id = "bite.disbelief", scene = "bite", ideaId = "bite_disbelief",
        shape = "fragment", voiceWeights = ALL,
        requires = { "wound.bite", "time.same_day" },
        asserts = "The writer was bitten on the named part on the day of writing.",
        variants = {
            { id = "a",
                text = "Bitten. Today. On the {part}.\n\nI keep reading that word back like it might turn into a different one." },
            { id = "b", requires = { "background.fear.turning" },
                text = "Bitten on the {part}.\n\nOf all the things I was afraid of, this was always the one. I used to think naming it would help." },
        },
    },
    {
        id = "bite.blunt", scene = "bite", ideaId = "bite_bravado",
        shape = "terse_note", voiceWeights = { blunt_brave = 8, guarded_practical = 2 },
        requires = { "wound.bite" },
        asserts = "The writer has a bite on the named part.",
        variants = {
            { id = "a", text = "Got bit on the {part}.\n\nFigured I'd be the last one it happened to. Everybody figures that." },
            { id = "b", text = "Bite on the {part}.\n\nWell. At least I know how the story ends. Most people don't get that." },
        },
    },
    {
        id = "bite.watchful", scene = "bite", ideaId = "the_plan_had_a_line_for_this",
        shape = "list_and_aside", voiceWeights = { wry_watchful = 8, guarded_practical = 2 },
        requires = { "wound.bite" },
        asserts = "The writer has a bite on the named part.",
        variants = {
            { id = "a", text = "Bitten on the {part}.\n\nI planned for this. I had a whole list. The list didn't mention how quiet everything would get." },
            { id = "b", text = "The bite is on my {part}.\n\nI keep checking it, like checking will change something. It's the one thing on my list that isn't going to get better." },
        },
    },
    {
        id = "bite.warm", scene = "bite", ideaId = "bite_goodbyes",
        shape = "reflection", voiceWeights = { warm_candid = 8 },
        requires = { "wound.bite" },
        asserts = "The writer has a bite on the named part.",
        variants = {
            { id = "a", text = "I was bitten on the {part}.\n\nI keep thinking about who I'd want to say goodbye to, and how few of them are still anywhere." },
            { id = "b", requires = { "writer.still_with_player" },
                text = "A bite, on the {part}.\n\nI'm not ready. I don't think anybody is. I'm glad I'm not alone for it." },
        },
    },

    ---------------------------------------------------------------- symptoms
    {
        id = "symptoms.early_bite", scene = "symptoms", ideaId = "fever_begins",
        shape = "bare_note", voiceWeights = ALL,
        requires = { "symptoms.early", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has early fever symptoms.",
        variants = {
            { id = "a", text = "Feverish.\n\nI knew it was coming, and it still surprised me." },
            { id = "b", text = "It's started. Warm, then cold.\n\nI'd hoped I'd be the exception. Everyone must hope that." },
        },
    },
    {
        id = "symptoms.early_scratch", scene = "symptoms", ideaId = "maybe_the_scratch",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "symptoms.early", "infection.scratch_known" },
        asserts = "The writer, who had a recent scratch or cut, feels unwell.",
        variants = {
            { id = "a", text = "I feel sick. Could be the water. Could be anything.\n\nI'm not writing the other thing." },
            { id = "b", requires = { "anchor.scratch_worry.committed" },
                text = "Earlier I wrote, '{earlier_quote}'\n\nI feel sick today. I'm trying very hard not to connect those two things." },
        },
    },
    {
        id = "symptoms.early_unknown", scene = "symptoms", ideaId = "unwell",
        shape = "mundane_note", voiceWeights = ALL,
        requires = { "symptoms.early", "infection.cause_unknown" },
        asserts = "The writer feels unwell.",
        variants = {
            { id = "a", text = "Queasy and cold. Hoping it's something I ate." },
            { id = "b", text = "Under the weather.\n\nThat used to be a whole day off. Now it's just a thing I write down." },
        },
    },
    {
        id = "symptoms.mid_bite_guarded", scene = "symptoms", ideaId = "fever_worsening",
        shape = "fragment", voiceWeights = { guarded_practical = 8, blunt_brave = 4 },
        requires = { "symptoms.mid", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has worsening fever.",
        variants = {
            { id = "a", text = "Cold, then too hot. My hands shake while I write.\n\nNot much else to say that isn't obvious." },
            { id = "b", text = "Worse today.\n\nStill here. Still me. Writing that down while it's true." },
        },
    },
    {
        id = "symptoms.mid_bite_watchful", scene = "symptoms", ideaId = "fever_worsening",
        shape = "list_and_aside", voiceWeights = { wry_watchful = 8 },
        requires = { "symptoms.mid", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has worsening fever.",
        variants = {
            { id = "a", text = "Symptoms, because lists help: fever. Chills. A head full of static.\n\nThe list isn't helping." },
            { id = "b", text = "Things that are getting worse: the fever.\n\nThings that are getting better: nothing I can think of. I'll keep thinking." },
        },
    },
    {
        id = "symptoms.mid_bite_warm", scene = "symptoms", ideaId = "fever_worsening",
        shape = "reflection", voiceWeights = { warm_candid = 8 },
        requires = { "symptoms.mid", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has worsening fever.",
        variants = {
            { id = "a", text = "The fever's worse.\n\nI'm trying to spend the good hours being kind. There aren't as many of them." },
            { id = "b", requires = { "writer.still_with_player" },
                text = "Worse today.\n\nI don't want the others to remember me as frightened. I'm frightened. I'm writing it here so I don't have to be frightened out there." },
        },
    },
    {
        id = "symptoms.mid_other", scene = "symptoms", ideaId = "fear_dawning",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "symptoms.mid" }, forbids = { "infection.bite_known" },
        asserts = "The writer, who knows of no bite, has worsening fever.",
        variants = {
            { id = "a", requires = { "infection.scratch_known" },
                text = "Getting worse, not better.\n\nThe scratch is the only explanation I have, and I don't like it." },
            { id = "b", requires = { "infection.cause_unknown" },
                text = "Worse today. Fever, and I don't know from what.\n\nI've stopped hoping it was something I ate." },
        },
    },
    {
        id = "symptoms.late_bite_guarded", scene = "symptoms", ideaId = "near_the_end",
        shape = "fragment", voiceWeights = { guarded_practical = 8 },
        requires = { "symptoms.late", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has severe fever.",
        variants = {
            { id = "a", text = "Hard to write.\n\n{player}, if you read this: it wasn't your fault. It was a bite." },
            { id = "b", text = "Not long, I think.\n\nIf somebody finds this, I was {writer}. I did my share." },
        },
    },
    {
        id = "symptoms.late_bite_warm", scene = "symptoms", ideaId = "near_the_end",
        shape = "letter", voiceWeights = { warm_candid = 8 },
        requires = { "symptoms.late", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has severe fever.",
        variants = {
            { id = "a", text = "I don't have much left in me.\n\nI wanted to say it somewhere it would stay: I was glad of all of you. Even the hard days. Maybe especially those." },
            { id = "b", requires = { "writer.still_with_player" },
                text = "{player}, I hope you're the one who finds this.\n\nThank you for letting me come along. I would do it all again." },
        },
    },
    {
        id = "symptoms.late_bite_blunt", scene = "symptoms", ideaId = "near_the_end",
        shape = "terse_note", voiceWeights = { blunt_brave = 8 },
        requires = { "symptoms.late", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has severe fever.",
        variants = {
            { id = "a", text = "Not long now.\n\nDon't let me walk around afterwards. That's the one thing I'm asking." },
            { id = "b", text = "Burning up.\n\nNo regrets worth writing down. A few not worth writing down either." },
        },
    },
    {
        id = "symptoms.late_bite_watchful", scene = "symptoms", ideaId = "near_the_end",
        shape = "fragment", voiceWeights = { wry_watchful = 8 },
        requires = { "symptoms.late", "infection.bite_known" },
        asserts = "The writer, who knows of a bite, has severe fever.",
        variants = {
            { id = "a", text = "I keep losing words halfway through thinking them.\n\nIf this stops in the middle of a sentence, that's why." },
            { id = "b", text = "Planned for most things. Didn't plan for this part.\n\nWhoever has this book now: be careful. Be more careful than me." },
        },
    },
    {
        id = "symptoms.late_other", scene = "symptoms", ideaId = "near_the_end",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "symptoms.late" }, forbids = { "infection.bite_known" },
        asserts = "The writer, who knows of no bite, has severe fever.",
        variants = {
            { id = "a", requires = { "anchor.scratch_worry.committed" },
                text = "Earlier I wrote, '{earlier_quote}'\n\nIt wasn't nothing. It was the scratch." },
            { id = "b", requires = { "infection.cause_unknown" },
                text = "Something is very wrong with me.\n\nI never even saw it happen. I don't know which part of that is worse." },
        },
    },

    ---------------------------------------------- the group's decision (self)
    {
        id = "crisis_self.watch", scene = "crisis_self", ideaId = "being_watched",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "crisis.outcome.watch" },
        asserts = "The group decided to keep the writer under watch.",
        variants = {
            { id = "a", text = "They've decided to keep watching me instead of anything worse.\n\nI'm grateful. I'm also aware of how carefully everyone is being kind." },
            { id = "b", text = "Under watch.\n\nFair enough. I'd watch me too." },
        },
    },
    {
        id = "crisis_self.quarantine", scene = "crisis_self", ideaId = "kept_apart",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "crisis.outcome.quarantine" },
        asserts = "The group decided to keep the writer apart.",
        variants = {
            { id = "a", text = "They want me kept apart for now. It's the sensible thing.\n\nI would have decided the same. I'd just rather not have been the one it was about." },
            { id = "b", text = "Quarantine.\n\nI keep telling myself it's temporary. It is, one way or another." },
        },
    },
    {
        id = "crisis_self.exile", scene = "crisis_self", ideaId = "sent_away",
        shape = "decision_note", voiceWeights = ALL,
        requires = { "crisis.outcome.exile" },
        asserts = "The group decided the writer must leave.",
        variants = {
            { id = "a", text = "I'm to leave. They decided together.\n\nI understand it. I don't forgive it yet. Maybe I won't need to." },
            { id = "b", text = "They want me gone before it gets bad.\n\nI'd have said the same thing about somebody else. That doesn't help as much as it should." },
        },
    },
    {
        id = "crisis_self.self_exile", scene = "crisis_self", ideaId = "leaving_on_my_own",
        shape = "decision_note", voiceWeights = ALL,
        requires = { "crisis.outcome.self_exile" },
        asserts = "The writer chose to leave the group.",
        variants = {
            { id = "a", text = "I'm going before anyone has to ask me to.\n\nIt's the last useful thing I can do for them." },
            { id = "b", text = "Leaving.\n\nNobody has to be brave about me. That part's mine." },
        },
    },
    {
        id = "crisis_self.mercy", scene = "crisis_self", ideaId = "quick_ending",
        shape = "reflection", voiceWeights = ALL,
        requires = { "crisis.outcome.mercy" },
        asserts = "The group agreed on a mercy ending for the writer.",
        variants = {
            { id = "a", text = "They've agreed it will be quick when the time comes.\n\nI'm not angry about it. I thought I would be." },
            { id = "b", text = "It's decided. When it's time, someone will make sure I don't come back.\n\nThat's a kindness. I'm going to keep calling it that." },
        },
    },
    {
        id = "crisis_self.self_sacrifice", scene = "crisis_self", ideaId = "my_choice",
        shape = "decision_note", voiceWeights = ALL,
        requires = { "crisis.outcome.self_sacrifice" },
        asserts = "The writer chose how their ending will go.",
        variants = {
            { id = "a", text = "I've made my choice about how this ends.\n\nIt's mine to make. I'd like that to be remembered." },
        },
    },

    ------------------------------------------------- another person's bite
    {
        id = "crisis_other.protective", scene = "crisis_other", ideaId = "defending_them",
        shape = "resolution", voiceWeights = ALL,
        requires = { "crisis.other_bitten_known", "stance.protective" },
        asserts = "The writer knows the named person was bitten.",
        variants = {
            { id = "a", requires = { "crisis.learned.witnessed_bite" },
                text = "{subject} was bitten. I saw it.\n\nWe don't abandon our own. Writing it down so I can't take it back." },
            { id = "b", text = "{subject} is bitten.\n\nNobody is putting {subject} out in the cold while I'm around. Not while {subject} is still {subject}." },
        },
    },
    {
        id = "crisis_other.compassionate", scene = "crisis_other", ideaId = "courage_to_tell",
        shape = "reflection", voiceWeights = ALL,
        requires = { "crisis.other_bitten_known", "stance.compassionate" },
        asserts = "The writer knows the named person was bitten.",
        variants = {
            { id = "a", requires = { "crisis.learned.confession" },
                text = "{subject} told us about the bite.\n\nThat took more courage than anything I've done lately." },
            { id = "b", text = "{subject} was bitten.\n\nWhatever we decide, I want {subject} to have somewhere quiet, and not to be alone." },
        },
    },
    {
        id = "crisis_other.pragmatic", scene = "crisis_other", ideaId = "plan_not_funeral",
        shape = "terse_note", voiceWeights = ALL,
        requires = { "crisis.other_bitten_known", "stance.pragmatic" },
        asserts = "The writer knows the named person was bitten.",
        variants = {
            { id = "a", text = "{subject} is infected.\n\nWe need a plan, not a funeral. Not yet." },
            { id = "b", text = "{subject}: bitten.\n\nSomeone has to think about the next part while everyone feels the first part. Fine. Me." },
        },
    },
    {
        id = "crisis_other.fearful", scene = "crisis_other", ideaId = "ashamed_of_fear",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "crisis.other_bitten_known", "stance.fearful" },
        asserts = "The writer knows the named person was bitten.",
        variants = {
            { id = "a", text = "{subject} is bitten and still here with us.\n\nI hate myself a little for how much that scares me." },
            { id = "b", text = "{subject} was bitten.\n\nI keep counting the steps between us. I'm not proud of it." },
        },
    },
    {
        id = "crisis_other.authoritarian", scene = "crisis_other", ideaId = "hard_decision",
        shape = "resolution", voiceWeights = ALL,
        requires = { "crisis.other_bitten_known", "stance.authoritarian" },
        asserts = "The writer knows the named person was bitten.",
        variants = {
            { id = "a", text = "{subject} was bitten. Someone has to be clear-headed about what that means.\n\nIt'll probably be me. I'd rather it wasn't." },
        },
    },
    {
        id = "crisis_other.symptoms_seen", scene = "crisis_other", ideaId = "seeing_it",
        shape = "fragment", voiceWeights = ALL,
        requires = { "crisis.other_bitten_known", "crisis.learned.visible_symptoms" },
        asserts = "The writer has seen the named person's infection symptoms.",
        variants = {
            { id = "a", text = "I can see it in {subject} now.\n\nI don't know what I'm supposed to do with my face when I look." },
        },
    },

    -------------------------------------------------------------------- loss
    {
        id = "loss.guarded", scene = "loss", ideaId = "difficulty_accepting_loss",
        shape = "bare_statement", voiceWeights = { guarded_practical = 8, blunt_brave = 2 },
        requires = { "death.known_to_writer" },
        asserts = "The named person is dead and the writer knows it.",
        variants = {
            { id = "a", text = "{subject} is dead.\n\nI know what the words mean. They still don't seem to have much to do with {subject}." },
            { id = "b", text = "{subject} is dead.\n\nDon't know what to put after that." },
        },
    },
    {
        id = "loss.warm", scene = "loss", ideaId = "missing_them",
        shape = "reflection", voiceWeights = { warm_candid = 8 },
        requires = { "death.known_to_writer" },
        asserts = "The named person is dead and the writer knows it.",
        variants = {
            { id = "a", requires = { "death.subject_close" },
                text = "We lost {subject}.\n\nI keep thinking of things to tell {subject}. Then I remember." },
            { id = "b", requires = { "death.witnessed", "time.same_day" },
                text = "I was there when {subject} died.\n\nI don't want to write the rest. I just didn't want today to pass without {subject}'s name in it." },
            { id = "c", forbids = { "death.subject_close" },
                text = "{subject} is gone.\n\nI didn't know {subject} as well as I should have. I thought there'd be time." },
        },
    },
    {
        id = "loss.blunt", scene = "loss", ideaId = "gone",
        shape = "fragment", voiceWeights = { blunt_brave = 8 },
        requires = { "death.known_to_writer" },
        asserts = "The named person is dead and the writer knows it.",
        variants = {
            { id = "a", text = "{subject}'s gone.\n\nThat's all. That's the whole entry." },
            { id = "b", requires = { "death.witnessed" },
                text = "Saw it happen to {subject}.\n\nI've seen a lot of people die. It's different when it's someone you know." },
        },
    },
    {
        id = "loss.watchful", scene = "loss", ideaId = "no_plan_for_it",
        shape = "private_admission", voiceWeights = { wry_watchful = 8 },
        requires = { "death.known_to_writer" },
        asserts = "The named person is dead and the writer knows it.",
        variants = {
            { id = "a", text = "{subject} died.\n\nI had a plan for almost everything. Not for that." },
            { id = "b", forbids = { "death.subject_close" },
                text = "{subject} is dead. We weren't close.\n\nI still keep expecting to see {subject} around the corner." },
        },
    },

    ---------------------------------------------------- care from the player
    {
        id = "care_player.guarded", scene = "care_player", ideaId = "unsure_what_help_costs",
        shape = "private_admission", voiceWeights = { guarded_practical = 8, wry_watchful = 4 },
        requires = { "care.player_bandaged_writer", "relationship.guarded" },
        asserts = "The player bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "{player} bandaged my {part}.\n\nI keep wondering what that costs me. Maybe nothing. I'm not used to nothing." },
            { id = "b", text = "Bandage from {player}. On the {part}.\n\nDon't much like being the one who needs something." },
        },
    },
    {
        id = "care_player.warming", scene = "care_player", ideaId = "difficulty_saying_thanks",
        shape = "reluctant_gratitude", voiceWeights = { guarded_practical = 8, blunt_brave = 2 },
        requires = { "care.player_bandaged_writer" }, forbids = { "relationship.guarded" },
        asserts = "The player bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "{player} bandaged my {part}. Felt better not doing it on my own.\n\nI've been trying to find a less embarrassing way of writing 'thank you.' Haven't found one." },
            { id = "b", requires = { "player.he" },
                text = "{player} bandaged my {part}.\n\nI was glad for the help. That's what I should say to him. Not much of a speech. Still easier to put it here." },
            { id = "c", requires = { "player.she" },
                text = "{player} bandaged my {part}.\n\nI was glad for the help. That's what I should say to her. Not much of a speech. Still easier to put it here." },
        },
    },
    {
        id = "care_player.warm", scene = "care_player", ideaId = "letting_someone_help",
        shape = "reflection", voiceWeights = { warm_candid = 8 },
        requires = { "care.player_bandaged_writer" },
        asserts = "The player bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "{player} wrapped my {part}, and I let myself be looked after, which isn't like me.\n\nI think it might be like me now." },
            { id = "b", requires = { "relationship.guarded" },
                text = "{player} bandaged my {part}.\n\nIt's strange how much a small kindness weighs when you weren't expecting one." },
        },
    },
    {
        id = "care_player.blunt", scene = "care_player", ideaId = "owing_one",
        shape = "terse_note", voiceWeights = { blunt_brave = 8 },
        requires = { "care.player_bandaged_writer" },
        asserts = "The player bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "{player} patched up my {part}.\n\nOwe one. Keeping count." },
            { id = "b", requires = { "care.wound_bleeding" },
                text = "Was bleeding from the {part}. {player} sorted it.\n\nNot going to make a thing of it. Writing it here instead." },
        },
    },
    {
        id = "care_player.watchful", scene = "care_player", ideaId = "useful_and_kind",
        shape = "list_and_aside", voiceWeights = { wry_watchful = 8 },
        requires = { "care.player_bandaged_writer" }, forbids = { "relationship.guarded" },
        asserts = "The player bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "Note to self: {player} knows how to dress a wound. My {part} can confirm.\n\nUseful. Also kind. I'm counting both." },
        },
    },

    ------------------------------------------------- care from a companion
    {
        id = "care_companion.plain", scene = "care_companion", ideaId = "paying_back_care",
        shape = "mundane_note", voiceWeights = { guarded_practical = 8, blunt_brave = 6 },
        requires = { "care.companion_bandaged_writer" },
        asserts = "The named survivor bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "{subject} bandaged my {part}.\n\nI'll have to find a way to be useful back." },
            { id = "b", text = "{subject} bandaged my {part}.\n\nGood to have someone around who knows which end of a bandage is which." },
        },
    },
    {
        id = "care_companion.warm", scene = "care_companion", ideaId = "cared_for_by_the_scared",
        shape = "reflection", voiceWeights = { warm_candid = 8, wry_watchful = 6 },
        requires = { "care.companion_bandaged_writer" },
        asserts = "The named survivor bandaged the named part of the writer.",
        variants = {
            { id = "a", text = "{subject} took care of my {part}.\n\nThere's something about being looked after by someone who's also scared. It counts double." },
            { id = "b", text = "{subject} dressed my {part}.\n\nAdding {subject} to the short list of people I'd trust with anything." },
        },
    },

    ------------------------------------------------------------- self care
    {
        id = "care_self.plain", scene = "care_self", ideaId = "managing_alone",
        shape = "mundane_note", voiceWeights = { guarded_practical = 8, blunt_brave = 8 },
        requires = { "care.writer_bandaged_self" },
        asserts = "The writer bandaged their own named body part.",
        variants = {
            { id = "a", text = "Bandaged my own {part}. It'll do." },
            { id = "b", requires = { "care.used_torn_clothing" },
                text = "Tore up some clothing to wrap my {part}.\n\nClothes are easier to replace than blood." },
        },
    },
    {
        id = "care_self.reflective", scene = "care_self", ideaId = "getting_good_at_it",
        shape = "private_admission", voiceWeights = { warm_candid = 8, wry_watchful = 8 },
        requires = { "care.writer_bandaged_self" },
        asserts = "The writer bandaged their own named body part.",
        variants = {
            { id = "a", text = "Took care of my own {part}.\n\nI'm getting better at it. I'd rather not be." },
            { id = "b", text = "Dressed my own {part}.\n\nAdded bandages to the list of things I worry about. It's a long list." },
        },
    },

    ---------------------------------------------------- caring for someone
    {
        id = "care_other.player", scene = "care_other", ideaId = "helping_back",
        shape = "mundane_note", voiceWeights = ALL,
        requires = { "care.writer_bandaged_player" },
        asserts = "The writer bandaged the player's named body part.",
        variants = {
            { id = "a", text = "Bandaged {player}'s {part}.\n\nFeels good to be the one helping, for once." },
            { id = "b", requires = { "relationship.close" },
                text = "{player} got hurt. I dressed the {part}.\n\nMy hands were steady. I wasn't." },
            { id = "c", text = "Patched up {player}'s {part}. We're even. For now." },
        },
    },
    {
        id = "care_other.companion", scene = "care_other", ideaId = "looking_after_them",
        shape = "mundane_note", voiceWeights = ALL,
        requires = { "care.writer_bandaged_companion" },
        asserts = "The writer bandaged the named survivor's named body part.",
        variants = {
            { id = "a", text = "Bandaged {subject}'s {part}.\n\nNice to be useful with something other than a weapon." },
            { id = "b", text = "Dressed the wound on {subject}'s {part}.\n\nWe look after each other. That's most of what we have." },
        },
    },

    ------------------------------------------------------------ shared escape
    {
        id = "escape.guarded", scene = "escape", ideaId = "too_shaken_to_describe",
        shape = "short_fragment", voiceWeights = { guarded_practical = 8, blunt_brave = 3 },
        requires = { "danger.escape_with_player" },
        asserts = "The writer and the player got clear of danger together.",
        variants = {
            { id = "a", requires = { "time.night", "writer.shaken" },
                text = "We got out. I'm not writing the rest tonight." },
            { id = "b", requires = { "time.night" },
                text = "Out. Both of us.\n\nThat is enough for tonight." },
            { id = "c", text = "Close one. We both got clear.\n\nThat's the part worth writing down." },
        },
    },
    {
        id = "escape.warm", scene = "escape", ideaId = "glad_we_are_both_here",
        shape = "reflection", voiceWeights = { warm_candid = 8 },
        requires = { "danger.escape_with_player" },
        asserts = "The writer and the player got clear of danger together.",
        variants = {
            { id = "a", requires = { "writer.shaken" },
                text = "We made it out, {player} and me. My heart is still going too fast to write properly.\n\nI'm so glad we're both here." },
            { id = "b", text = "Got out of a bad spot with {player}.\n\nI keep thinking about how quickly it could have gone the other way. Then I stop, because it didn't." },
        },
    },
    {
        id = "escape.blunt", scene = "escape", ideaId = "enjoyed_it_too_much",
        shape = "terse_note", voiceWeights = { blunt_brave = 8 },
        requires = { "danger.escape_with_player" },
        asserts = "The writer and the player got clear of danger together.",
        variants = {
            { id = "a", text = "Close one. Got clear.\n\nDon't love how much I enjoyed the running part." },
        },
    },
    {
        id = "escape.watchful", scene = "escape", ideaId = "fewer_next_times",
        shape = "list_and_aside", voiceWeights = { wry_watchful = 8 },
        requires = { "danger.escape_with_player" },
        asserts = "The writer and the player got clear of danger together.",
        variants = {
            { id = "a", text = "Got out. Both of us.\n\nNote for next time: fewer next times." },
        },
    },

    ------------------------------------------------------- healed (callback)
    {
        id = "healed.scratch", scene = "healed", ideaId = "worry_that_came_to_nothing",
        shape = "quote_and_correction", voiceWeights = ALL,
        requires = { "anchor.scratch_worry.committed", "wound.all_healed", "symptoms.none",
            "time.callback_due" },
        forbids = { "infection.bite_known" },
        asserts = "An earlier page holds the quoted worry; the writer now has no wound and no fever.",
        variants = {
            { id = "a", text = "Earlier I wrote, '{earlier_quote}'\n\nIt's healed. I can stop looking now. I probably won't, straight away." },
            { id = "b", text = "Went back and read '{earlier_quote}'\n\nNothing came of it. I'm told this is what relief feels like." },
        },
    },

    ----------------------------------------------------- watching someone hurt
    {
        id = "witnessed_hurt.plain", scene = "witnessed_hurt", ideaId = "saw_it_happen",
        shape = "shaken_note", voiceWeights = { guarded_practical = 8, blunt_brave = 4 },
        requires = { "witness.saw_hurt" },
        asserts = "The writer was nearby when the named person was hurt.",
        variants = {
            { id = "a", requires = { "time.same_day" },
                text = "Watched {subject} get hurt today. It happened fast. It always does." },
            { id = "b", text = "Saw {subject} take a hit.\n\nI keep replaying it and putting myself a few steps closer." },
        },
    },
    {
        id = "witnessed_hurt.badly", scene = "witnessed_hurt", ideaId = "saw_it_badly",
        shape = "fragment", voiceWeights = ALL,
        requires = { "witness.saw_hurt", "witness.badly" },
        asserts = "The writer was nearby when the named person was badly hurt.",
        variants = {
            { id = "a", text = "{subject} got hurt badly and I saw all of it.\n\nI'm not going to describe it. I'll remember it well enough without help." },
        },
    },
    {
        id = "witnessed_hurt.warm", scene = "witnessed_hurt", ideaId = "too_slow_to_help",
        shape = "private_admission", voiceWeights = { warm_candid = 8, wry_watchful = 3 },
        requires = { "witness.saw_hurt" },
        asserts = "The writer was nearby when the named person was hurt.",
        variants = {
            { id = "a", text = "{subject} got hurt and I couldn't get there fast enough.\n\nI hope it looked worse than it was." },
            { id = "b", text = "Saw {subject} get hurt.\n\nWe don't talk about how close these things come. I'll write about it instead." },
        },
    },
    {
        id = "witnessed_hurt.gallows", scene = "witnessed_hurt", ideaId = "the_noise_they_made",
        shape = "dark_joke", voiceWeights = { blunt_brave = 8, wry_watchful = 4 },
        requires = { "witness.saw_hurt" }, forbids = { "witness.badly" },
        asserts = "The writer was nearby when the named person was lightly hurt.",
        variants = {
            { id = "a", text = "{subject} got knocked about a bit.\n\nI would like to say I didn't laugh at the noise {subject} made. I would like to say that." },
            { id = "b", text = "Saw {subject} get hurt. Nothing serious, from what I saw.\n\nAdding it to the list of things I should have seen coming. Long list. None of it helps." },
        },
    },

    ------------------------------------------------------------ conflict
    {
        id = "conflict.started", scene = "conflict", ideaId = "said_too_much",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "conflict.started_argument" },
        asserts = "The writer started an argument with the named person.",
        variants = {
            { id = "a", text = "Had it out with {subject}. I said what I'd been holding in.\n\nFeels better. Feels worse. Both." },
            { id = "b", text = "I snapped at {subject}.\n\nSome of it needed saying. The way I said it didn't." },
        },
    },
    {
        id = "conflict.confronted", scene = "conflict", ideaId = "got_told",
        shape = "reluctant_note", voiceWeights = ALL,
        requires = { "conflict.was_confronted" },
        asserts = "The named person started an argument with the writer.",
        variants = {
            { id = "a", text = "{subject} had a go at me today.\n\nMaybe {subject} had a point. I'm not ready to write that down properly yet.",
                requires = { "time.same_day" } },
            { id = "b", text = "Got told off by {subject}.\n\nI'm taking notes, apparently. In here. Where {subject} can't argue back." },
        },
    },
    {
        id = "conflict.shoved_them", scene = "conflict", ideaId = "shoved_a_friend",
        shape = "shaken_note", voiceWeights = ALL,
        requires = { "conflict.shoved_them" },
        asserts = "The writer shoved the named person during an argument.",
        variants = {
            { id = "a", text = "I shoved {subject}.\n\nI don't know who that was. I don't like that it was me." },
            { id = "b", requires = { "conflict.someone_hurt" },
                text = "It went too far with {subject}. Somebody got hurt.\n\nWe've got enough out there trying to hurt us without doing it to each other." },
        },
    },
    {
        id = "conflict.got_shoved", scene = "conflict", ideaId = "got_shoved",
        shape = "terse_note", voiceWeights = ALL,
        requires = { "conflict.got_shoved" },
        asserts = "The named person shoved the writer during an argument.",
        variants = {
            { id = "a", text = "{subject} shoved me. Over nothing, or over everything. Hard to tell the difference lately." },
            { id = "b", text = "{subject} put hands on me today.\n\nI'm going to be very calm about it. In writing. Only in writing.",
                requires = { "time.same_day" } },
        },
    },

    ----------------------------------------------------------- breakdowns
    {
        id = "breakdown.bottle", scene = "breakdown", ideaId = "smashed_a_bottle",
        shape = "dark_joke", voiceWeights = ALL,
        requires = { "breakdown.bottle_smash" },
        asserts = "The writer smashed a bottle while letting off stress.",
        variants = {
            { id = "a", text = "Smashed a bottle against a wall. Felt amazing for one second.\n\nThen I had to watch where I stepped." },
            { id = "b", text = "Broke a bottle on purpose.\n\nNote: glass goes further than you'd think. Note two: so does embarrassment." },
        },
    },
    {
        id = "breakdown.furniture", scene = "breakdown", ideaId = "hit_the_furniture",
        shape = "dark_joke", voiceWeights = ALL,
        requires = { "breakdown.furniture_hit" },
        asserts = "The writer hit furniture while letting off stress.",
        variants = {
            { id = "a", text = "I took it out on the furniture.\n\nBetter the furniture than anyone here. The furniture agrees, I assume." },
            { id = "b", text = "Hit the furniture. It started it." },
        },
    },
    {
        id = "breakdown.vent", scene = "breakdown", ideaId = "lost_temper",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "breakdown.vent" },
        asserts = "The writer lost their temper out loud.",
        variants = {
            { id = "a", text = "Lost my temper at nothing in particular.\n\nNothing in particular had it coming." },
            { id = "b", text = "Shouted at the air for a while.\n\nThe air took it well. I didn't." },
        },
    },
    {
        id = "breakdown.restless", scene = "breakdown", ideaId = "could_not_sit_still",
        shape = "mundane_note", voiceWeights = ALL,
        requires = { "breakdown.restless_break" },
        asserts = "The writer had a restless episode.",
        variants = {
            { id = "a", text = "Couldn't sit still. Paced until my legs voted against it." },
        },
    },
    {
        id = "breakdown.withdraw", scene = "breakdown", ideaId = "needed_to_be_alone",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "breakdown.withdraw" },
        asserts = "The writer withdrew to be alone for a while.",
        variants = {
            { id = "a", text = "Needed to be on my own for a while. I took it.\n\nI'm better for it, I think." },
            { id = "b", text = "Hid from everyone for a bit. Not from danger. From people. From myself, mostly." },
        },
    },
    {
        id = "breakdown.shutdown", scene = "breakdown", ideaId = "could_not_move",
        shape = "fragment", voiceWeights = ALL,
        requires = { "breakdown.shutdown" },
        asserts = "The writer had a shutdown episode.",
        variants = {
            { id = "a", text = "There was a stretch where I couldn't do anything at all.\n\nI'm writing this so I know it ended." },
            { id = "b", text = "Everything stopped for a while. Me included.\n\nIt started again. I'm counting that as a win." },
        },
    },

    ------------------------------------------------------------------ joy
    {
        id = "joy.rallying", scene = "joy", ideaId = "a_good_day",
        shape = "light_note", voiceWeights = ALL,
        requires = { "joy.rallying" },
        asserts = "The writer had an upswing of good spirits.",
        variants = {
            { id = "a", text = "Felt good today. Actually good.\n\nFor once I believed we'd be all right, and nobody had to talk me into it." },
            { id = "b", text = "Good day. Don't jinx it." },
        },
    },
    {
        id = "joy.caretaker", scene = "joy", ideaId = "wanted_to_look_after_everyone",
        shape = "light_note", voiceWeights = ALL,
        requires = { "joy.caretaker" },
        asserts = "The writer had an upswing of wanting to look after others.",
        variants = {
            { id = "a", text = "Spent the day wanting to look after everyone.\n\nIt probably helped me more than them. I'll take it." },
        },
    },
    {
        id = "joy.lifted", scene = "joy", ideaId = "good_mood_spread",
        shape = "light_note", voiceWeights = ALL,
        requires = { "joy.lifted_by_someone" },
        asserts = "The named person's good spirits reached the writer.",
        variants = {
            { id = "a", text = "{subject} was in a good mood and it rubbed off.\n\nI didn't know I still had that in me." },
            { id = "b", text = "Something went right today, mostly because of {subject}.\n\nI've checked, and it's still right." },
        },
    },

    ------------------------------------------------------- a broken promise
    {
        id = "promise_broken.plain", scene = "promise_broken", ideaId = "supply_run_that_never_came",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "promise.supply_run_missed" },
        asserts = "The supply run the writer was expecting did not happen in time.",
        variants = {
            { id = "a", text = "The supply run we talked about never happened.\n\nI know things come up. I also know what was said." },
            { id = "b", text = "Supply run: still waiting.\n\nI've started keeping score, and I don't like that I have." },
            { id = "c", text = "No supply run.\n\nNoted. Underlined, if I'm honest." },
        },
    },

    -------------------------------------------------- talking with the player
    {
        id = "talk.praised", scene = "talk", ideaId = "being_told_well_done",
        shape = "reluctant_gratitude", voiceWeights = { guarded_practical = 8, wry_watchful = 6 },
        requires = { "talk.praised" },
        asserts = "The player praised the writer.",
        variants = {
            { id = "a", text = "{player} told me I did well.\n\nNot used to that. Writing it down so it counts twice." },
            { id = "b", requires = { "talk.praised_for.worked" },
                text = "Got praised for keeping the gear in order.\n\nOf all the things to be proud of. I am, though." },
        },
    },
    {
        id = "talk.praised_warm", scene = "talk", ideaId = "being_told_well_done",
        shape = "reflection", voiceWeights = { warm_candid = 8, blunt_brave = 6 },
        requires = { "talk.praised" },
        asserts = "The player praised the writer.",
        variants = {
            { id = "a", text = "{player} said something kind about what I did.\n\nI'm going to keep that one for the bad days." },
            { id = "b", requires = { "talk.praised_for.rescued_player" },
                text = "{player} thanked me for pulling the danger off.\n\nI'd do it again. I'd rather not have to. Both true." },
            { id = "c", text = "Got a well done from {player}.\n\nDon't let it go to your head. Too late." },
        },
    },
    {
        id = "talk.past", scene = "talk", ideaId = "told_them_about_before",
        shape = "reflection", voiceWeights = ALL,
        requires = { "talk.shared_past" },
        asserts = "The writer told the player a piece of their past.",
        variants = {
            { id = "a", text = "Told {player} a bit about my life before.\n\nFirst time I've said any of it out loud in a while." },
            { id = "b", requires = { "talk.revealed.fear" },
                text = "Told {player} what scares me most.\n\nNow two of us know. That's either safer or worse." },
            { id = "c", requires = { "talk.revealed.occupation" },
                text = "{player} asked what I used to do.\n\nIt's strange saying your old job out loud now. It sounds like a story about somebody else." },
            { id = "d", requires = { "talk.revealed.home" },
                text = "Talked about home today.\n\nIt felt far away and close at the same time." },
            { id = "e", requires = { "talk.revealed.keepsake" },
                text = "Told {player} about what I carry with me.\n\nNobody's heard about it in a long time. It felt like letting someone into a locked room." },
            { id = "f", requires = { "talk.revealed.habit" },
                text = "Told {player} about one of my habits.\n\nI fully expect to be teased about it. I've made my peace." },
        },
    },
    {
        id = "talk.encouraged", scene = "talk", ideaId = "a_pep_talk",
        shape = "light_note", voiceWeights = ALL,
        requires = { "talk.encouraged" },
        asserts = "The player encouraged the writer and it helped.",
        variants = {
            { id = "a", text = "{player} took a minute to encourage me.\n\nI needed it more than I let on." },
            { id = "b", text = "Pep talk from {player}. It worked, which is annoying." },
            { id = "c", text = "{player} said the right thing at the right time.\n\nSuspicious. Grateful. Mostly grateful." },
        },
    },

    ------------------------------------------------------- studying the dead
    {
        id = "study.generic", scene = "study", ideaId = "looked_at_the_dead",
        shape = "reflection", voiceWeights = ALL,
        requires = {},
        asserts = "The writer spent time studying a dead zombie up close.",
        variants = {
            { id = "a", text = "Spent a while looking at one of the dead up close.\n\nThey were a person once. I made myself look at that part too." },
            { id = "b", text = "Studied a corpse, like a lunatic. Learned nothing.\n\nWill probably do it again." },
        },
    },
    {
        id = "study.outfits", scene = "study", ideaId = "dressed_for_something",
        shape = "dark_joke", voiceWeights = ALL,
        requires = {},
        asserts = "The writer studied a dead zombie wearing the named kind of clothing.",
        variants = {
            { id = "santa", requires = { "study.outfit.santa" },
                text = "Found a dead Santa. Spent a while looking at him.\n\nI'm not going to recover from that emotionally." },
            { id = "wedding", requires = { "study.outfit.wedding" },
                text = "Studied one of them dressed for a wedding.\n\nI hope they at least got to the cake." },
            { id = "clergy", requires = { "study.outfit.clergy" },
                text = "Looked over one dressed as a priest.\n\nEven they didn't get a pass." },
            { id = "party", requires = { "study.outfit.party" },
                text = "One of them was dressed for a party.\n\nThe party's over. Sorry. Somebody had to say it." },
            { id = "jockey", requires = { "study.outfit.jockey" },
                text = "Studied a dead jockey. I didn't know we had any around here.\n\nNow we have one fewer." },
            { id = "hazmat", requires = { "study.outfit.hazmat" },
                text = "One of them was in a hazmat suit. It didn't help.\n\nI'm trying not to think about what that means." },
            { id = "military", requires = { "study.outfit.military" },
                text = "Looked at a dead soldier.\n\nIf they couldn't handle this, I don't know what the rest of us are doing." },
            { id = "law", requires = { "study.outfit.law" },
                text = "Studied one in a police uniform.\n\nDidn't feel like joking about that one." },
            { id = "medic", requires = { "study.outfit.medic" },
                text = "One in scrubs.\n\nThe people who were supposed to fix this got it first." },
            { id = "inmate", requires = { "study.outfit.inmate" },
                text = "Studied an inmate.\n\nSomebody finally got out. Just not the way anyone wanted." },
            { id = "food", requires = { "study.outfit.food" },
                text = "One of them was still in a fast food uniform.\n\nStill on shift, technically." },
            { id = "sports", requires = { "study.outfit.sports" },
                text = "One was dressed for sport. Fitness didn't save them.\n\nGood news for my cardio, I suppose." },
            { id = "office", requires = { "study.outfit.office" },
                text = "One in office clothes.\n\nSomewhere, a report is still overdue." },
            { id = "raider", requires = { "study.outfit.raider" },
                text = "Studied one of the bandit types.\n\nDidn't feel bad. Wrote this down to check whether I should." },
            { id = "home", requires = { "study.outfit.home" },
                text = "One of them was dressed for a day at home.\n\nDied on a day off. That's the detail that got me." },
            { id = "patient", requires = { "study.outfit.patient" },
                text = "One in a hospital gown.\n\nThey were already sick before any of this. That's not fair. None of it is." },
            { id = "fire", requires = { "study.outfit.fire" },
                text = "Studied a firefighter. Still in the gear.\n\nThey ran toward it. Of course they did." },
            { id = "reporter", requires = { "study.outfit.reporter" },
                text = "One of them looked like a news reporter.\n\nFinally, a story nobody's covering." },
        },
    },

    ---------------------------------------------------------- respects paid
    {
        id = "respects.plain", scene = "respects", ideaId = "a_moment_for_a_stranger",
        shape = "reflection", voiceWeights = ALL,
        requires = {},
        asserts = "The writer stopped to give a dead body a moment.",
        variants = {
            { id = "a", text = "Stopped to give one of the dead a moment. It seemed like someone should." },
            { id = "b", text = "Paid my respects to a stranger.\n\nI hope someone does that for me. Actually, I hope nobody has to." },
            { id = "c", requires = { "respects.memento_seen" },
                text = "There was a {memento} with one of the bodies.\n\nI left it where it was. It wasn't mine to take." },
        },
    },

    --------------------------------------------------------- small comforts
    {
        id = "workout.plain", scene = "workout", ideaId = "exercised",
        shape = "light_note", voiceWeights = ALL,
        requires = {},
        asserts = "The writer did a workout.",
        variants = {
            { id = "a", text = "Did a workout. Everything hurts.\n\nApparently that's the point." },
            { id = "b", text = "Exercised. Cardio is a survival skill now.\n\nI used to say that as a joke." },
            { id = "c", text = "Worked out. For a few minutes it felt like an ordinary life with extra zombies." },
        },
    },
    {
        id = "reading.plain", scene = "reading", ideaId = "read_something",
        shape = "light_note", voiceWeights = ALL,
        requires = {},
        asserts = "The writer read the named item.",
        variants = {
            { id = "a", text = "Read some of '{item}'.\n\nNobody in it had to check the doors twice. I liked that." },
            { id = "b", text = "Read '{item}'. The world ended and I'm still reading.\n\nSo I suppose that's who I am." },
            { id = "c", text = "Did some reading. Better than thinking." },
        },
    },
    {
        id = "washed.plain", scene = "washed", ideaId = "got_clean",
        shape = "light_note", voiceWeights = ALL,
        requires = {},
        asserts = "The writer washed up.",
        variants = {
            { id = "a", text = "Washed up. Felt human for about ten minutes." },
            { id = "b", text = "Washed the dirt off.\n\nIt felt like putting something down that I'd been carrying." },
            { id = "c", requires = { "weather.cold" }, text = "Washed in cold water, in cold weather.\n\nI am clean and I am furious about it." },
        },
    },
    {
        id = "repair.plain", scene = "repair", ideaId = "fixed_something",
        shape = "mundane_note", voiceWeights = ALL,
        requires = {},
        asserts = "The writer repaired the named item.",
        variants = {
            { id = "a", text = "Patched up the {item}. It'll hold.\n\nMost things do, if you ask nicely." },
            { id = "b", text = "Looked after the {item}.\n\nThings that are looked after last longer. People too." },
            { id = "c", text = "Fixed something today. Small job. Felt big." },
        },
    },

    --------------------------------------------------------- fights and tales
    {
        id = "fight_story.counted", scene = "fight_story", ideaId = "counted_them",
        shape = "tally_and_feeling", voiceWeights = { guarded_practical = 8, wry_watchful = 6 },
        requires = { "fight.many_kills" },
        asserts = "The writer killed the stated number of zombies in one fight.",
        variants = {
            { id = "a", text = "Put down {kills} of them {place}. I counted.\n\nI want to feel proud, and mostly I feel tired." },
            { id = "b", text = "{kills} of them.\n\nEach one had a name once. I don't know any of them. That's the part I can live with." },
        },
    },
    {
        id = "fight_story.brag", scene = "fight_story", ideaId = "future_tall_tale",
        shape = "light_note", voiceWeights = { blunt_brave = 8, warm_candid = 3 },
        requires = { "fight.many_kills" },
        asserts = "The writer killed the stated number of zombies in one fight.",
        variants = {
            { id = "a", text = "{kills} of them {place}.\n\nIf anyone asks, it was more." },
            { id = "b", requires = { "fight.bare_hands" },
                text = "Did it with my bare hands. {kills} of them.\n\nI'm going to be insufferable about this." },
            { id = "c", text = "Did most of it with a {weapon}.\n\nI've started thinking of it as a friend. That's probably a bad sign." },
            { id = "d", requires = { "fight.player_there" },
                text = "{player} saw the whole thing. Good. Now there's a witness." },
        },
    },
    {
        id = "fight_story.grabbed", scene = "fight_story", ideaId = "had_hold_of_me",
        shape = "shaken_note", voiceWeights = ALL,
        requires = { "fight.grabbed" },
        asserts = "The writer was grabbed during a fight and survived it.",
        variants = {
            { id = "a", text = "One of them had hold of me {place}. I got free.\n\nI can still feel where its hands were." },
            { id = "b", text = "Got grabbed. Got loose. Got lucky.\n\nIn that order. I'm not going to think about a different order." },
        },
    },
    {
        id = "fight_story.hurt", scene = "fight_story", ideaId = "hurt_but_standing",
        shape = "terse_note", voiceWeights = ALL,
        requires = { "fight.hurt" },
        asserts = "The writer was hurt during a fight and survived it.",
        variants = {
            { id = "a", text = "Got hurt in the fight {place}.\n\nStill here. The fight isn't." },
            { id = "b", text = "Got hurt in a fight.\n\nStill here. The fight isn't. I'm counting that as the score." },
        },
    },
    {
        id = "tale_told.inflated", scene = "tale_told", ideaId = "the_numbers_grow",
        shape = "light_note", voiceWeights = ALL,
        requires = { "tale.told", "tale.inflated" },
        asserts = "The writer retold a fight story with a bigger number than the real count.",
        variants = {
            { id = "a", text = "Told the story again. It was {kills}. It's {told} now.\n\nIt'll be more by winter." },
            { id = "b", text = "For the record, since nobody else will keep one: it was {kills}.\n\nI've been saying {told}." },
            { id = "c", text = "Told the old story again. It was {kills}, not {told}.\n\nIt isn't really about the number anymore." },
        },
    },
    {
        id = "tale_told.legend", scene = "tale_told", ideaId = "it_has_a_name_now",
        shape = "light_note", voiceWeights = ALL,
        requires = { "tale.told", "tale.legend" },
        asserts = "The writer's fight story now carries the stated title.",
        variants = {
            { id = "a", text = "It's called {title} now.\n\nI didn't pick the name. I didn't not pick it either." },
        },
    },
    {
        id = "tale_told.honest", scene = "tale_told", ideaId = "kept_it_honest",
        shape = "light_note", voiceWeights = ALL,
        requires = { "tale.told" }, forbids = { "tale.inflated" },
        asserts = "The writer told a fight story with the true count.",
        variants = {
            { id = "a", text = "Told the others about the fight. Kept the numbers honest.\n\nFirst time's free." },
        },
    },

    ----------------------------------------------------------- work and burial
    {
        id = "work.planks_plain", scene = "work", ideaId = "a_job_that_ends",
        shape = "tally_and_background", voiceWeights = { guarded_practical = 8, wry_watchful = 6 },
        requires = { "work.planks" }, forbids = { "grief.active" },
        asserts = "The writer sawed the stated number of planks.",
        variants = {
            { id = "a", requires = { "count.many" },
                text = "{count} planks.\n\nThere's something to be said for a job that ends." },
            { id = "b", requires = { "count.many", "background.habit.counts_supplies" },
                text = "Made {count} planks. Counted them twice. Old habit.\n\nThe number didn't change. It never does, and I check anyway." },
        },
    },
    {
        id = "work.planks_light", scene = "work", ideaId = "arms_filed_complaint",
        shape = "light_note", voiceWeights = { blunt_brave = 8, warm_candid = 6 },
        requires = { "work.planks" }, forbids = { "grief.active" },
        asserts = "The writer sawed planks.",
        variants = {
            { id = "a", requires = { "count.many" }, text = "Cut {count} planks. My arms have filed a complaint." },
            { id = "b", text = "Sawing all day, or what felt like it.\n\nWe're building something. Nice to be building something." },
        },
    },
    {
        id = "work.grief", scene = "work", ideaId = "work_distracting_from_grief",
        shape = "irritated_self_observation", voiceWeights = ALL,
        requires = { "grief.active" },
        asserts = "The writer did production work while grieving the named person.",
        variants = {
            { id = "a", text = "Worked until I stopped thinking. It gave me something to do besides think about {grieved}.\n\nThen I felt bad about that. Then I got annoyed with myself for feeling bad. Very productive." },
            { id = "b", text = "Kept my hands busy today.\n\nThen I thought of {grieved} again. I don't think there's a correct way to do this." },
        },
    },
    {
        id = "work.trees", scene = "work", ideaId = "felled_trees",
        shape = "light_note", voiceWeights = ALL,
        requires = { "work.trees" }, forbids = { "grief.active" },
        asserts = "The writer felled the stated number of trees.",
        variants = {
            { id = "a", requires = { "count.one" }, text = "Cut down a tree. It didn't fight back.\n\nNice change." },
            { id = "b", requires = { "count.many" }, text = "Felled {count} trees.\n\nThe woods are quieter than town. For now." },
        },
    },
    {
        id = "burial.strangers", scene = "burial", ideaId = "buried_strangers",
        shape = "reflection", voiceWeights = ALL,
        requires = { "burial.buried" },
        asserts = "The writer buried the stated number of dead strangers.",
        variants = {
            { id = "a", requires = { "count.one" },
                text = "Buried one of the dead. I didn't know their name.\n\nI thought about what it might have been." },
            { id = "b", requires = { "count.many" },
                text = "Buried {count} strangers.\n\nSomebody has to. Today it was me." },
            { id = "c", text = "Grave work.\n\nThe dead don't complain. That's more than I can say for my back." },
        },
    },
    {
        id = "burial.burned", scene = "burial", ideaId = "pyre_duty",
        shape = "dark_note", voiceWeights = ALL,
        requires = { "burial.burned" },
        asserts = "The writer burned the stated number of bodies on a pyre.",
        variants = {
            { id = "a", text = "Burned bodies today.\n\nThe smell stays in your clothes. I'm told it stays in your head too." },
            { id = "b", requires = { "count.many" }, text = "Pyre duty. {count} of them.\n\nI stood upwind and thought about nothing, very hard." },
        },
    },
    {
        id = "burial.friend", scene = "burial", ideaId = "buried_a_friend",
        shape = "bare_statement", voiceWeights = ALL,
        requires = { "burial.friend" },
        asserts = "The writer buried the named fallen companion in their own grave.",
        variants = {
            { id = "a", requires = { "time.same_day" },
                text = "I buried {subject} today. In {subject}'s own grave, with a name on it.\n\nIt's the only thing I could still do." },
            { id = "b", text = "Put {subject} in the ground myself.\n\nThat felt important. It still does." },
            { id = "c", text = "Buried {subject}. I kept thinking I should say something.\n\nI didn't know what, so I'm writing it here: I'm sorry." },
        },
    },

    ------------------------------------------------------------------ mercy
    {
        id = "mercy.done", scene = "mercy", ideaId = "i_was_the_one",
        shape = "bare_statement", voiceWeights = ALL,
        requires = { "mercy.performed" },
        asserts = "The writer carried out the mercy decision for the named bitten person.",
        variants = {
            { id = "a", text = "{subject} was bitten, and it was decided. I was the one who did it.\n\nI don't want to write anything else." },
            { id = "b", text = "I did it. {subject} won't come back.\n\nThat was the point. That's what I keep telling myself." },
            { id = "c", text = "There were good reasons it had to be me.\n\nI keep going over them. None of them help. I'm sorry, {subject}." },
        },
    },

    ------------------------------------------------------------- milestones
    {
        id = "milestone.week", scene = "milestone", ideaId = "a_week_together",
        shape = "light_note", voiceWeights = ALL,
        requires = { "milestone.week" },
        asserts = "The writer has been with the player for at least a week.",
        variants = {
            { id = "a", text = "A week with {player}, give or take.\n\nLonger than I gave it." },
            { id = "b", text = "{days} days. Still breathing. Still here." },
        },
    },
    {
        id = "milestone.month", scene = "milestone", ideaId = "a_month_together",
        shape = "reflection", voiceWeights = ALL,
        requires = { "milestone.month" },
        asserts = "The writer has been with the player for at least thirty days.",
        variants = {
            { id = "a", text = "A month with {player}.\n\nI've stopped counting days and started counting on people. That's a sentence I wrote. I'm leaving it." },
            { id = "b", text = "{days} days.\n\nI've survived longer with {player} than I ever planned for." },
        },
    },
    {
        id = "milestone.hundred", scene = "milestone", ideaId = "a_hundred_days",
        shape = "reflection", voiceWeights = ALL,
        requires = { "milestone.hundred" },
        asserts = "The writer has been with the player for at least a hundred days.",
        variants = {
            { id = "a", text = "{days} days with {player}.\n\nI didn't think I'd see a hundred of anything." },
        },
    },

    ---------------------------------------------------------- quiet days
    {
        id = "quiet.nothing", scene = "quiet", ideaId = "nothing_to_report",
        shape = "light_note", voiceWeights = ALL,
        requires = {},
        asserts = "Nothing is claimed beyond a quiet day.",
        variants = {
            { id = "a", text = "Nothing to report. That's the best kind of entry." },
            { id = "b", text = "Quiet day. I'm learning to enjoy those without waiting for the other shoe." },
            { id = "c", requires = { "writer.bored" },
                text = "Bored enough to write about being bored.\n\nThis is a new low. Or a new high. Hard to say." },
        },
    },
    {
        id = "quiet.weather", scene = "quiet", ideaId = "the_weather",
        shape = "mundane_note", voiceWeights = ALL,
        requires = {},
        asserts = "The weather the writer can see right now.",
        variants = {
            { id = "rain", requires = { "weather.rain" },
                text = "Rain. It covers the sound of us.\n\nIt also covers the sound of them. I try not to think about that part." },
            { id = "snow", requires = { "weather.snow" },
                text = "Snow. The dead leave tracks now.\n\nSo do we." },
            { id = "fog", requires = { "weather.fog" },
                text = "Fog. Couldn't see far.\n\nNeither could they, I hope." },
            { id = "cold", requires = { "weather.cold" },
                text = "Cold enough to see my breath.\n\nAt least that means I've still got some." },
            { id = "hot", requires = { "weather.hot" },
                text = "Too hot to think.\n\nThe dead smell worse in the heat. So do we, to be fair." },
        },
    },
    {
        id = "quiet.body", scene = "quiet", ideaId = "how_i_feel",
        shape = "mundane_note", voiceWeights = ALL,
        requires = {},
        asserts = "How the writer's body feels right now.",
        variants = {
            { id = "hungry", requires = { "writer.hungry" },
                text = "Hungry. My stomach has opinions and none of them are polite." },
            { id = "thirsty", requires = { "writer.thirsty" },
                text = "Thirsty. I think about water the way I used to think about holidays." },
            { id = "tired", requires = { "writer.tired" },
                text = "Tired all the way down.\n\nA few lines before sleep, so today counts for something." },
            { id = "wet", requires = { "writer.wet" },
                text = "Soaked through.\n\nI will never take dry socks for granted again." },
            { id = "cold", requires = { "writer.has_cold" },
                text = "I've got a cold.\n\nOf all the things that could kill you now, a cold feels insulting." },
            { id = "drunk", requires = { "writer.drunk" },
                text = "Had a drink. Or two.\n\nWriting this very carefully." },
            { id = "pain", requires = { "writer.in_pain" },
                text = "Everything aches. Some of it is new.\n\nMost of it is just the world." },
        },
    },
    {
        id = "quiet.mood", scene = "quiet", ideaId = "my_head_today",
        shape = "private_admission", voiceWeights = ALL,
        requires = {},
        asserts = "The writer's current mood.",
        variants = {
            { id = "hopeful", requires = { "writer.hopeful" },
                text = "Today felt like we might actually make it.\n\nI'm writing it down in case I need proof later." },
            { id = "low", requires = { "writer.low" },
                text = "Low today. No reason I can point to.\n\nMaybe that's the reason." },
            { id = "unhappy", requires = { "writer.unhappy" },
                text = "Bad day in my head. Nothing out there did it.\n\nThat's the frustrating part." },
        },
    },
    {
        id = "quiet.company", scene = "quiet", ideaId = "who_is_here",
        shape = "reflection", voiceWeights = ALL,
        requires = { "writer.still_with_player" },
        asserts = "Who the writer is currently travelling with.",
        variants = {
            { id = "just_us", requires = { "group.just_us" },
                text = "It's just {player} and me.\n\nSmall group. Small is easier to keep alive." },
            { id = "crowd", requires = { "group.crowd" },
                text = "There are more of us now. More mouths, more hands, more people to lose.\n\nMostly I'm glad." },
            { id = "days", requires = { "time.days_together" },
                text = "{days} days with {player}.\n\nI've stopped being surprised by it." },
            { id = "camp", requires = { "place.at_base", "time.evening" },
                text = "Quiet evening at camp.\n\nWalls, a roof, people I know. I used to call that an ordinary day." },
        },
    },
    {
        id = "quiet.grief", scene = "quiet", ideaId = "still_missing_them",
        shape = "private_admission", voiceWeights = ALL,
        requires = { "grief.active" },
        asserts = "The writer is still grieving the named person.",
        variants = {
            { id = "a", requires = { "grief.recovering" },
                text = "Still miss {grieved}. Less sharply now.\n\nI don't know how I feel about that." },
            { id = "b", text = "Thought about {grieved} again.\n\nI keep doing that. I don't want to stop." },
        },
    },
    {
        id = "quiet.season", scene = "quiet", ideaId = "the_season",
        shape = "reflection", voiceWeights = ALL,
        requires = {},
        asserts = "The current season.",
        variants = {
            { id = "summer", requires = { "season.summer" },
                text = "Summer. It used to mean something else." },
            { id = "autumn", requires = { "season.autumn" },
                text = "The leaves are turning. Nobody's raking them.\n\nI keep noticing that. Winter's coming whether we're ready or not." },
            { id = "winter", requires = { "season.winter" },
                text = "Winter now.\n\nIf we get to spring, I'm going to be unbearable about it." },
        },
    },
    {
        id = "quiet.canon", scene = "quiet", ideaId = "who_i_was",
        shape = "background_association", voiceWeights = ALL,
        requires = {},
        asserts = "A fixed fact of the writer's own background.",
        variants = {
            { id = "tea", requires = { "background.habit.makes_tea" },
                text = "Thought about tea. Making a cup used to fix most things.\n\nSome habits are just hope with a kettle." },
            { id = "hum", requires = { "background.habit.hums" },
                text = "I used to hum all the time. I've gone quiet.\n\nI'd like to start again, when it's safe. If." },
            { id = "count", requires = { "background.habit.counts_supplies" },
                text = "Counted our supplies in my head again.\n\nI know what we have. I count anyway." },
            { id = "notes", requires = { "background.habit.keeps_notes" },
                text = "I always kept notes. Now I keep this.\n\nSame habit. Heavier pages." },
            { id = "exits", requires = { "background.habit.checks_exits" },
                text = "I still find the exits first in every room.\n\nI don't think I'll ever stop." },
            { id = "tools", requires = { "background.habit.cleans_tools" },
                text = "I keep wanting to clean my tools.\n\nSome habits are how you stay sane." },
            { id = "dark", requires = { "background.fear.the_dark", "time.night" },
                text = "Dark out. I've always hated the dark.\n\nIt has so much more in it now." },
            { id = "alone", requires = { "background.fear.being_alone", "writer.still_with_player" },
                text = "Not alone today. I notice that every single day." },
            { id = "turning", requires = { "background.fear.turning", "time.night" },
                text = "Some nights I think about turning.\n\nTonight's one of them. I'm writing it down so it has somewhere to go." },
            { id = "letdown", requires = { "background.fear.letting_people_down" },
                text = "Nobody needed me to be brave today.\n\nI'm relieved. I'm also a bit ashamed of how relieved." },
            { id = "home", requires = { "home_known" },
                text = "Thinking about {home_name}.\n\nWondering what's left of it. Wondering if anyone's left in it." },
            { id = "honesty", requires = { "background.value.honesty" },
                text = "I used to think honesty was simple.\n\nIt's simpler in here." },
            { id = "courage", requires = { "background.value.courage" },
                text = "Courage used to be a word for other people.\n\nNow it's just what you call getting up." },
        },
    },
}

-- First visits to notable places, one passage family per kind of place.
local PLACE_PASSAGES = {
    police = { "Walked into a police station like we owned it.\n\nI suppose we do now." },
    prison = { "Went into the prison.\n\nEverybody's serving a life sentence now. Some of us are just serving it outside." },
    church = { "Went into a church. Didn't pray. Didn't not pray.",
        "A church. Nobody was saved there either." },
    bar = { "Walked into a bar.\n\nThere's a joke there, and I'm too tired to find it." },
    liquor = { "A liquor store. Strictly for medicinal purposes. Strictly." },
    whiskey = { "Found where they made the whiskey.\n\nResisted. Mostly." },
    brewery = { "A brewery.\n\nTook a moment of silence for all that beer." },
    school = { "Walked through a school.\n\nI didn't stay in those rooms long." },
    library = { "A library. All that knowledge.\n\nNone of it about this." },
    gunstore = { "A gun store.\n\nFirst time in weeks the world has made sense to me. That's concerning." },
    pharmacy = { "A pharmacy. I read labels for longer than I needed to." },
    hospital = { "We went into the hospital.\n\nI'm not going to write about the hospital." },
    morgue = { "The morgue.\n\nThe one place that was ready for this." },
    dentist = { "A dentist's office. Even now, it made my teeth hurt." },
    spiffos = { "Spiffo's.\n\nSomebody should still be made to wear the costume." },
    jays = { "Jay's Chicken.\n\nI miss fried food more than I miss some people." },
    grocery = { "Walked the aisles of a grocery store like it was a normal day.\n\nIt was nice, for a minute." },
    gas = { "A gas station.\n\nI keep expecting someone to ask if I'm paying for that." },
    garage = { "A mechanic's garage.\n\nIt felt like a place where things still got fixed." },
    firehouse = { "A fire station.\n\nThey were supposed to come when you called." },
    army = { "An army depot.\n\nIf they couldn't hold it, I don't know what the rest of us are doing out here." },
    theatre = { "A movie theater.\n\nNothing's playing. Nothing's going to." },
    bowling = { "A bowling alley.\n\nLife used to have so many silly places in it." },
    stripclub = { "We went into a strip club. For supplies.\n\nThat is the sentence I'm writing. Supplies." },
    lab = { "A laboratory.\n\nSomebody in here was supposed to be working on this." },
    motel = { "A motel room.\n\nSomebody's last vacation." },
    laundry = { "A laundromat.\n\nThe world ended, and I still thought about separating the colors." },
    gym = { "A gym.\n\nNobody's working on their fitness anymore. Well. We are. Differently." },
    music = { "A music store. I wanted to play something.\n\nI didn't. Noise is dangerous now." },
    books = { "A bookstore.\n\nI could live here, if living here didn't mean dying here." },
    zippee = { "A Zippee Market.\n\nStill open twenty-four hours, in a sense." },
}

local placeGroups = {}
for group in pairs(PLACE_PASSAGES) do placeGroups[#placeGroups + 1] = group end
table.sort(placeGroups)
for _, group in ipairs(placeGroups) do
    local variants = {}
    for index, passage in ipairs(PLACE_PASSAGES[group]) do
        variants[#variants + 1] = { id = string.char(96 + index), text = passage }
    end
    packets[#packets + 1] = {
        id = "place." .. group, scene = "place", ideaId = "place_" .. group,
        shape = "light_note", voiceWeights = ALL, requires = { "place." .. group },
        asserts = "The writer was present on the party's first visit to this kind of place.",
        variants = variants,
    }
end
packets[#packets + 1] = {
    id = "place.old_workplace", scene = "place", ideaId = "place_like_my_old_job",
    shape = "reflection", voiceWeights = { guarded_practical = 9, warm_candid = 9, blunt_brave = 9,
        wry_watchful = 9 },
    requires = { "place.old_workplace" },
    asserts = "The writer entered a kind of place they used to work in.",
    variants = {
        { id = "a", text = "Walked into a place just like where I used to work.\n\nI knew where everything was. That was the worst part." },
    },
}

-- A few of the heavier entries already written above also darken with the
-- weather or the hour, when that is simply true at the time of writing.
packets[#packets + 1] = {
    id = "loss.rain", scene = "loss", ideaId = "rain_for_them",
    shape = "bare_statement", voiceWeights = ALL,
    requires = { "death.known_to_writer", "weather.rain" },
    asserts = "The named person is dead and it is raining as the writer writes.",
    variants = {
        { id = "a", text = "{subject} is dead.\n\nIt's raining, which feels like the world making an effort." },
    },
}

packets[#packets + 1] = {
    id = "interior.dread", scene = "interior", ideaId = "sound_in_the_walls",
    shape = "light_note", voiceWeights = ALL, requires = { "interior.dread" },
    asserts = "A sound caused the writer's environmental stress to rise while the player stayed calm.",
    variants = {
        { id = "a", text = "Heard something in the building today. Nobody else seemed bothered.\n\nI was." },
        { id = "b", text = "A sound in the walls put every nerve on edge. It passed. The walls are still here." },
    },
}
packets[#packets + 1] = {
    id = "interior.panic", scene = "interior", ideaId = "panic_and_breath",
    shape = "reflection", voiceWeights = ALL, requires = { "interior.panic" },
    asserts = "The writer experienced a native panic transition.",
    variants = {
        { id = "a", text = "Panic got hold of me today.\n\nI got my breathing back before it got the rest." },
        { id = "b", text = "Hands shaking. Breath too fast. Then, eventually, neither. Writing that down matters." },
    },
}
packets[#packets + 1] = {
    id = "interior.nicotine", scene = "interior", ideaId = "wanting_a_smoke",
    shape = "light_note", voiceWeights = ALL, requires = { "interior.nicotine" },
    asserts = "The smoker experienced native nicotine withdrawal.",
    variants = {
        { id = "a", text = "Wanted a cigarette badly enough to say it out loud.\n\nThe dead have not improved my habits." },
        { id = "b", text = "No cigarettes today. Apparently the end of the world still expects me to quit." },
    },
}

packets.version = Catalog.VERSION
Catalog.packets = packets

function Catalog.voiceWeightsFor(archetype)
    return Catalog.ARCHETYPE_VOICE_WEIGHTS[archetype]
        or Catalog.ARCHETYPE_VOICE_WEIGHTS.practical
end

return Catalog
