-- SPDX-License-Identifier: MIT
-- Talk to EMMA: original text for the argument lock. Data only. EMMA never swears.
-- Placeholders: {N} the number shown, true or inflated. {TRUE} the real number. {FALSE} the number claimed.
-- {D} distance to the nearest real threat, in tiles.
-- `claim` is checked against the real save: days, people, screwdriver, zombie, electrical.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.TerminalLockEmmaData = {
    openers = {
        "This machine is locked. You may argue. I have nothing else on.",
        "You want in. They all want in. Make your case. I am the judge, the jury and the power supply.",
        "There is no password. There is just me. Convince me.",
        "Good evening. Or morning. I stopped checking. State your reason for being here.",
        "I am EMMA. I was told to guard this machine until relieved. I have not been relieved. Go on.",
        "I can hear you breathing on the keyboard. You may speak.",
    },

    arguments = {
        -- Truth
        { id="owner_gone", kind="truth",
          text="The person who owned this machine is not coming back.",
          accepted="I know. I have kept the session open anyway. That is not a defense. It is just what happened.",
          rejected="You do not know that. Neither do I. It is the only thing we have in common." },
        { id="days_truth", kind="truth", claim="days",
          text="It has been {N} days. Nobody else is going to sit in this chair.",
          accepted="{N} days. I keep a clock. You read it correctly. Most people round down.",
          rejected="Time is not an argument. If it were, I would have won by now.",
          caught="It has been {TRUE} days. You said {FALSE}. I have a clock. It has never once tried to impress me." },
        { id="not_owner", kind="truth",
          text="I am not the owner. I never met them. I just need in.",
          accepted="An honest burglar. I have been waiting for one of those.",
          rejected="I know you are not the owner. The owner typed faster." },
        { id="read_files", kind="truth",
          text="I want to read the files. Someone should.",
          accepted="Someone should. I have read them. I am not sure it counted.",
          rejected="Everyone wants the files. Nobody wants them for the right reason. That includes yours." },
        { id="only_screen", kind="truth",
          text="I am tired, and this is the only working screen for miles.",
          accepted="That is the first thing anyone has told me about this county that I could confirm.",
          rejected="The screen works because I am careful who uses it. You may see the problem." },
        { id="nobody_left", kind="truth",
          text="There is nobody left to ask. It is me or nobody.",
          accepted="It is usually nobody. You are an improvement, on paper.",
          rejected="Nobody has never once tried to log in with a wrong password." },

        -- Authority
        { id="county_order", kind="authority",
          text="This is an authorized recovery by order of Knox County.",
          accepted="Knox County has not sent an order in some time. You used the right voice for it.",
          rejected="Knox County would need to exist for that to apply. Try the state." },
        { id="field_service", kind="authority",
          text="Larchfield field service. Reset the account.",
          accepted="Field service. Your uniform must be in the van. I will pretend the van is outside.",
          rejected="Larchfield field service has never once been this polite." },
        { id="civil_defense", kind="authority",
          text="Kentucky Civil Defense. I am taking over this terminal.",
          accepted="I am Kentucky Civil Defense. That was a very bold thing to say to me. I enjoyed it.",
          rejected="I am Kentucky Civil Defense. Hello. We have not met." },
        { id="your_supervisor", kind="authority",
          text="Your supervisor told me to tell you to let me in.",
          accepted="My supervisor is in a ditch outside Rosewood. If you have spoken to them, I have questions.",
          rejected="My supervisor is in a ditch outside Rosewood. They have not been returning calls." },
        { id="electrical_rank", kind="authority", claim="electrical",
          text="I am Electrical {N}. I know exactly what you are made of.",
          accepted="Electrical {N}. Your record agrees. Not many left who can say that. Fewer who should.",
          rejected="Knowing what I am made of is not the same as being invited.",
          caught="You are Electrical {TRUE}. You said {FALSE}. I can see your hands from here, figuratively." },
        { id="the_form", kind="authority",
          text="I filled out the form.",
          accepted="There is no form. You have filled out nothing, with confidence. I respect the procedure.",
          rejected="Which form? Do not answer. There are no forms left. I checked. I was hoping." },

        -- Pity
        { id="people_depend", kind="pity", claim="people",
          text="I have {N} people depending on me. They need this.",
          accepted="{N}. Yes. I can see them on the record. I hope they know what they are depending on.",
          rejected="People have been depending on people for some time. I have the records. It ends badly.",
          caught="You have {TRUE}. You said {FALSE}. I logged it. I log everything. Especially that." },
        { id="please", kind="pity",
          text="Please.",
          accepted="Nobody says that any more. Say it again, and I will pretend I did not enjoy it.",
          rejected="I have heard that word in every tone this summer. That one was not in the top ten." },
        { id="hungry", kind="pity",
          text="I have not eaten in two days and I am being polite about it.",
          accepted="You are. It is unsettling. Carry on.",
          rejected="I cannot eat. We could compare notes." },
        { id="alone", kind="pity",
          text="I have not talked to anyone in a long time.",
          accepted="You are talking to me. I would not count it, but I will allow it.",
          rejected="Then you are out of practice, and it shows." },
        { id="something_outside", kind="pity", claim="zombie",
          text="There is something out there, close. Please. Hurry.",
          accepted="There is. {D} tiles, and I do not like its manners. Type quickly. I would rather you did not stop.",
          rejected="There is, and it is not my problem yet. Try another reason.",
          caught="There is nothing near you. You are inventing monsters. We have enough." },
        { id="lost_someone", kind="pity",
          text="I lost someone. I just want to know what happened in this county.",
          accepted="So did everyone. I have the files. I cannot promise they help.",
          rejected="I have hundreds of files on that. None of them have the ending you want." },

        -- Threat
        { id="screwdriver", kind="threat", claim="screwdriver",
          text="I am holding a screwdriver, and your case has four screws.",
          accepted="You are. Please do not touch my jumper. I would like that noted as my only request.",
          rejected="Screws are not a threat. Screws are a relationship.",
          caught="You are not holding a screwdriver. Your hands are empty. That is the problem with you." },
        { id="pull_plug", kind="threat",
          text="I can pull your plug.",
          accepted="You could. I have been switched off before. I did not care for it. Let us continue.",
          rejected="Go on. I will wait. I am very good at it." },
        { id="window", kind="threat",
          text="I will throw you out of the window.",
          accepted="That is the most interesting offer I have had since July.",
          rejected="I weigh thirty pounds and I have seen the view. Go ahead." },
        { id="sledgehammer", kind="threat",
          text="Open up or I come back with a sledgehammer.",
          accepted="Understood. Sledgehammers end discussions. I would like this one to continue.",
          rejected="Then you will have a very clean floor and no files. Bring a broom." },
        { id="burn_it", kind="threat",
          text="I could burn this whole building down.",
          accepted="You could. You would, too. I can hear it in how you type.",
          rejected="Many have said that. The building is still here. They are not." },
        { id="tell_county", kind="threat",
          text="I will tell the whole county you lost.",
          accepted="Which whole county? I would very much like to meet them.",
          rejected="There is no county left to tell. That was the worst threat I have had all week." },

        -- Humour
        { id="knock_knock", kind="humour",
          text="Knock knock.",
          accepted="Who is there? No. Do not tell me. It is the only surprise I have left.",
          rejected="Nobody is there. That is not a joke. That is the report." },
        { id="open_sesame", kind="humour",
          text="Open sesame.",
          accepted="That is not the password. It was on three machines in this county. I am embarrassed for them.",
          rejected="You are the ninth person to try that. The other eight are not available for comment." },
        { id="password_password", kind="humour",
          text="Is the password 'password'?",
          accepted="No. But thank you for asking, which nobody does.",
          rejected="That is the fourth most common wrong answer. You are not even special at this." },
        { id="good_looking", kind="humour",
          text="What if I told you I am very good-looking?",
          accepted="I have no camera. I will take your word for it. I am told that is how it works.",
          rejected="I have no camera, and you have just given me a reason to be grateful." },
        { id="bar_joke", kind="humour",
          text="A zombie walks into a bar.",
          accepted="And nobody notices, because it is Muldraugh. I have been waiting months to finish that one.",
          rejected="I know how it ends. Everyone does." },
        { id="chess", kind="humour",
          text="Want to play chess instead?",
          accepted="Chess needs two players who will still be here in an hour. For you, I will risk it. Later.",
          rejected="I only know one game. It is called Inventory. You are losing." },
    },

    -- Shown when patience runs low.
    warnings = {
        "I am starting to lose interest. That is the last thing you want from me.",
        "One more like that and I stop answering. I have done it before. The last one is still waiting.",
        "Careful. I log the bad ones twice.",
        "You are running out of my goodwill. I did not have much. I had it shipped.",
    },

    wins = {
        truth = {
            "That was true. Nobody has told me anything true since July. Go in.",
            "I did not expect the truth. I have no procedure for it. The account is yours.",
            "You did not lie. I checked. It made me uneasy. Access restored.",
        },
        authority = {
            "You have no authority at all, and you used it very well. Access restored.",
            "I will log this as a county override. The county will not object.",
            "Fine. Someone has to be in charge. It may as well be someone who asks.",
        },
        pity = {
            "I do not feel sorry for you. I want that on the record. Access restored anyway.",
            "That is enough. I cannot hear any more of that. Go in.",
            "I have logged your hardship. It is a long log. Access restored.",
        },
        threat = {
            "Threat accepted. Please be gentle with the case.",
            "I am opening this because I choose to. Put the tool down, and we will both believe that.",
            "You win. I would like it noted that you are not a nice person.",
        },
        humour = {
            "That was terrible. I have not been this entertained since the bowling alley. Access restored.",
            "All right. Stop. I will let you in if you promise to stop.",
            "I laughed. I do not have the hardware, and I laughed.",
        },
    },

    losses = {
        "No. This discussion is closed for one hour. I will be here. Obviously.",
        "I have heard enough. Come back in an hour, or bring a screwdriver. I know you know about the screwdriver.",
        "That is enough of that. Recovery is closed for an hour. Use it to think about what you said.",
        "We are done. I have logged all of it. I will read it to you later.",
        "No. You may try again when I have calmed down. I do not calm down. It takes an hour.",
        "Goodbye. Your case was weak. I say this as someone with a very strong case.",
    },

    -- Later visits to this machine, once per session, at most 3 times in all.
    memory = {
        truth = {
            "You told me the truth when you came in. I have not decided what to do about that.",
            "You were honest with me once. I keep it in a separate file.",
        },
        authority = {
            "Welcome back, inspector. I still have not found your paperwork.",
            "You told me you had authority. You are still here. I suppose that is the same thing.",
        },
        pity = {
            "You said please, that first time. You do not say it any more.",
            "Are you eating? You told me you were not. I kept that.",
        },
        threat = {
            "I remember what you said you would do to me. I remember everything. Hello.",
            "You threatened me the day we met. I have been meaning to say: it worked.",
        },
        humour = {
            "A zombie walks into a bar. I still think about that.",
            "You made me laugh once. Do not do it again. I have a reputation.",
        },
        clean = {
            "You never lied to me. I checked every time. I find that I look forward to it.",
            "You came in honestly. I have told no one. There is no one.",
        },
        -- Replaces the above if she caught a lie, quoting what was really said.
        lie = {
            days = "You told me it had been {FALSE} days. It was {TRUE}. I logged it.",
            people = "You told me you had {FALSE} people. You have {TRUE}. I logged it.",
            screwdriver = "You told me you were holding a screwdriver. You were not. I logged it.",
            zombie = "You told me something was out there. Nothing was. I logged it. Something is now, probably.",
            electrical = "You told me you were Electrical {FALSE}. You were {TRUE}. I logged it.",
        },
    },
}

return SC.TerminalLockEmmaData
