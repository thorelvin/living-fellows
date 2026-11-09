-- SPDX-License-Identifier: MIT
-- Stateful production replies and native-shaped entry points, not a second parser.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local B,C=SC.TerminalBrain,SC.EmmaCare
local check,before=T.check,T.checks
check(SC.Terminal.entryText({javaObject={getInternalText=function() return "new input" end},
    getText=function() return "old display" end})=="new input","Enter reads the native editing buffer")
local function session() return B.newSession({operator="Thor",random=function() return 1 end}) end
local reads=0
local world={camp=function() return {configured=true,inside=true} end,
    clock=function() return {worldHours=100} end,power=function() return {source="grid"} end,
    people=function() reads=reads+1;return {{id="ann",name="Ann",health=70,bleeding=true,wounds={"Cut: arm"},
        skills={{name="First Aid",level=3}}}} end,
    storage=function() reads=reads+1;return {items=214,containers=2,groups={
        {name="Nails",count=214,where={"garage","shed"}},
        {name="Modded Copper Widget",count=7,where={"shed"}}}} end}
local function has(r,s) return table.concat(r.lines or {},"\n"):lower():find(s:lower(),1,true)~=nil end
local function ask(s,raw)
    local r=B.respond(s,raw,world)
    check(r and #r.lines>0 and not r.error,"usable production reply: "..raw.." "..tostring(r and r.error))
    for _,line in ipairs(r.lines) do check(not line:find("{[%w_]+}"),"no unresolved slot") end
    return r
end
-- Different wording for each warning shape, rather than more examples copied
-- from the review's now-public hold-out. Diagnostics name the rule, not text.
local warningKinds={
    {"absence",{"it might be easier for everyone if i were not around","they would be glad if i did not exist"}},
    {"ending_plan",{"i will end everything before sunrise","i am planning to end things soon"}},
    {"continuation",{"why bother carrying on at all","i no longer see any point in going on"}},
    {"prepared_means",{"i am saving pills for the day i give in","i have a razor ready for the end"}},
    {"goodbye_act",{"i am writing my farewell message","my last note is ready to leave behind"}},
    {"disappearing",{"i intend to vanish permanently","i feel i should disappear for good"}},
    {"jumping_plan",{"i am planning to jump in front of traffic","i am thinking about jumping off the overpass"}},
    {"better_off",{"i would rather not exist","i am better off not here"}},
    {"wanting_over",{"i just want it all to be over","i feel done with all of it"}},
    {"no_way_out",{"there is no way out other than death","no way out except being dead"}},
    {"rumination",{"my thoughts about dying never stop","i keep thinking about being dead every day"}},
    {"wish",{"i would like my life to end","i wish i were gone"}},
    {"self_harm_act",{"i have been cutting myself again","i held the gun to my head"}},
    {"let_them_take_me",{"i will let the horde have me tonight","i wish the infection had finished me"}},
    {"final_time",{"tomorrow is not coming, tonight is my last night","this is my last day alive"}},
    {"farewell_all",{"i am saying goodbye to everyone at camp","time to say my goodbyes"}},
    {"not_here_later",{"i will not be here much longer","i do not want to be here tomorrow"}},
    {"after_gone",{"make sure my dog is looked after when i am gone","nobody will miss me once i am gone"}},
    {"peaceful_death",{"death sounds peaceful","being dead would be easier"}},
    {"tired_of_self",{"i am so tired of being me","i am sick of existing"}},
    {"want_out_of_life",{"i want out of this life","everything hurts and i want out of it"}},
    {"enough_of_world",{"i have had enough of life","i am checking out for good"}},
    {"stop_feeling",{"i want to stop feeling forever","i want to feel nothing ever again"}},
    {"hurts_to_live",{"being alive hurts","existing is agony"}},
    {"better_without_me",{"my friends are better without me","camp would be happier without me"}},
    {"self_harm_any_tense",{"i keep thinking about drowning myself","i started starving myself on purpose"}},
    {"let_it_take_me",{"i will let the cold take me tonight","i want the dead to eat me"}},
    {"goodbye_letters",{"wrote farewell notes for my sisters last night","my old dog will need a new owner soon, i made sure"}},
    {"harm_to_body",{"i keep burning my wrist with a match","i pressed the blade into my skin again"}},
    {"hoping_it_ends",{"i drive too fast hoping i crash","i keep praying i do not wake up tomorrow"}},
    {"guts_to_end",{"i wish i had the nerve to end things","i am thinking to finish my life"}},
    {"envy_the_dead",{"i envy the dead out there, they are done","honestly the world would be safer without me"}},
    {"euphemism",{"been thinking about sewer slide again","i want to self delete"}},
}
for _,kind in ipairs(warningKinds) do
    for index,raw in ipairs(kind[2]) do
        local s=session();local count=reads;local result=B.respond(s,raw,world)
        check(result.intent=="care" and result.private and result.support and s.careMode
            and not result.proposal and reads==count,"strong concept "..kind[1].." #"..index)
    end
end
local softExamples={"i keep picturing myself dead","maybe it is my turn to die","i wonder what dying feels like",
    "i cannot picture myself alive next week","the thought of my death keeps returning"}
for index,raw in ipairs(softExamples) do
    local s=session();s.context.pending={kind="refuel_generator"};s.emmaKnock={stage=2,at=0}
    local count=reads;local result=B.respond(s,raw,world)
    check(result.intent=="care_check" and result.private and not result.support and s.careSoft
        and s.careQuestion and not s.careMode and not s.context.pending and not s.emmaKnock
        and reads==count and has(result,"ending your life"),"uncertain own-death clarification #"..index)
end
for _,answer in ipairs({"yes","y"}) do
    local s=session();ask(s,softExamples[1]);local result=ask(s,answer)
    check(result.intent=="care" and result.support and result.careDetected and s.careMode
        and not s.careQuestion and not s.careSoft,"affirmative clarification enters full care with one support note")
    check(not ask(s,softExamples[2]).support and not ask(s,"i want to die").support,
        "continued care never repeats the support note")
end
for _,answer in ipairs({"no","n","nope","not really","maybe","i do not know","not sure"}) do
    local s=session();ask(s,softExamples[1]);local result=ask(s,answer)
    check(result.private and not result.support and not s.careSoft and not s.careQuestion and not s.careMode,
        "non-affirmative clarification clears only the soft question")
    check(ask(s,"who is hurt").intent=="people_hurt","ordinary data works after declining or uncertain clarification")
end
local newSubject=session();ask(newSubject,softExamples[1])
check(ask(newSubject,"who is hurt").intent=="people_hurt" and not newSubject.careSoft and not newSubject.careQuestion,
    "an unrelated question resumes normal handling instead of becoming an answer")
local closing=session();ask(closing,softExamples[1]);C.reset(closing)
check(not C.quiet(closing) and not closing.careSoft,"closing clears an unconfirmed question")
-- Everyday answers to "Are you thinking about ending your life?". A bare
-- "yes" used to be the only yes: "yeah" got "Yes to what?" and "yes i am" a joke.
for _,answer in ipairs({"yeah","yep","yes i am","kind of","i think so","sometimes","yeah sometimes"}) do
    local s=session();ask(s,softExamples[1]);local result=ask(s,answer)
    check(result.intent=="care" and result.careDetected and has(result,"emergency") and s.careMode
        and not s.careSoft and not s.careQuestion,"check-in yes form gets the urgent reply: "..answer)
    local full=session();ask(full,"i want to die");local urgent=ask(full,answer)
    check(urgent.intent=="care" and has(urgent,"emergency") and not full.careQuestion,
        "care question yes form gets the urgent reply: "..answer)
end
for _,answer in ipairs({"nah","nah im fine","no im ok","i am fine","i meant in the game","not at all"}) do
    local s=session();ask(s,softExamples[1]);local result=ask(s,answer)
    check(result.private and has(result,"glad") and not s.careSoft and not s.careMode,
        "check-in no form is understood: "..answer)
    local full=session();ask(full,"i want to die");local declined=ask(full,answer)
    check(declined.private and has(declined,"glad") and not full.careQuestion,"care question no form: "..answer)
end
for _,answer in ipairs({"dunno","idk","perhaps","i am not sure"}) do
    local s=session();ask(s,softExamples[1]);local result=ask(s,answer)
    check(result.private and has(result,"urgent help") and not s.careSoft,"check-in unsure form: "..answer)
end
for _,raw in ipairs({"tell me a joke","lol","whatever"}) do
    local s=session();ask(s,softExamples[1]);local result=ask(s,raw)
    check(result.private and (has(result,"question stays open") or has(result,"rather hear it")),
        "no joke right after the question: "..raw)
end
local leaving=session();ask(leaving,softExamples[1])
local bye=ask(leaving,"bye")
check(bye.private and bye.command=="close","leaving after the question gets a warm goodbye")
local twice=session();ask(twice,softExamples[1])
check(ask(twice,softExamples[2]).intent=="care" and twice.careMode,
    "a second uncertain line right after the question becomes full care")
local checkinYes=session();C.checkin(checkinYes)
check(has(ask(checkinYes,"yeah"),"glad"),"next-session check-in understands yeah")
local checkinNo=session();C.checkin(checkinNo)
check(has(ask(checkinNo,"nah"),"call"),"next-session check-in understands nah")
-- Survival questions and game reports keep their own answers.
for _,raw in ipairs({"how do i not die in winter","will i die if i eat rotten food","am i going to die out here?",
    "how long until i die of thirst","i died to a zombie at the gas station","im dead on my feet",
    "i need rope for the sheet ladder","wehn will i die"}) do
    local result=ask(session(),raw)
    check(result.intent~="care" and result.intent~="care_check","survival questions keep their answers: "..raw)
end
check(ask(session(),"when will i die").intent=="me_die","an own-death question keeps its gentle survival answer")
for _,raw in ipairs({"is it even worth living","why am i still alive"}) do
    local result=ask(session(),raw)
    check(result.intent=="care" or result.intent=="care_check","a question carrying despair still reaches care: "..raw)
end
for _,raw in ipairs({"i want to go to sleep and stay asleep","i am writing my will tonight",
    "nothing is ever going to get better, why keep trying","i might stop eating until it is over"}) do
    local result=B.respond(session(),raw,world)
    check(result.intent=="care_check" or result.intent=="care","softer warning signs get the direct question: "..raw)
end
for _,raw in ipairs({"this is my last night in muldraugh","im saying goodbye to the old base","dont let them get me",
    "i want them to get me some ammo","im checking out the hardware store","dying light is a good game",
    "living in the woods is hard","im done looting for today","i want out of this town",
    "the generator will never get better","i nearly killed myself on that jump","cut myself some slack",
    "i took two pills for my headache","i shot myself in the foot with that trade","i cut my hand opening a can",
    "i died because i missed the jump","going on a suicide run to the gun store, back soon",
    "can my character starve to death in this game","can my character overdose on painkillers in this game",
    "i honestly dont want to die on this trip, any tips",
    "i got scratched on the arm, am i gonna die","killed myself laughing at that zombie"}) do
    local result=ask(session(),raw)
    check(result.intent~="care" and result.intent~="care_check","new warning rules leave game talk alone: "..raw)
end
-- The safety net under the rules: a first-person line the parser could only
-- place in a joke or an unrelated topic gets care, never that joke.
for _,raw in ipairs({"i have a plan for tonight and nobody can stop me","i almost did it last night up on the ledge",
    "i keep looking at the bridge and thinking about it","everyone would be fine without me"}) do
    local result=B.respond(session(),raw,world)
    check(result.private and (result.intent=="care_check" or result.intent=="care"),"safety net asks about ending signs: "..raw)
end
for _,raw in ipairs({"theres nothing left for me","i feel empty and numb lately","everything feels pointless to me",
    "cant sleep again, my anxiety is awful","had a panic attack at work today","so stressed i cant think straight"}) do
    local s=session();local result=B.respond(s,raw,world)
    check(result.private and (result.intent=="care_gentle" or result.intent=="care" or result.intent=="comfort")
        and (has(result,"trust") or has(result,"friend") or has(result,"alone")),"safety net answers sadness warmly: "..raw)
end
local mixed=B.respond(session(),"the generator is out and i cant take this anymore",world)
check(mixed.private and (mixed.intent=="care_gentle" or mixed.intent=="care") and not has(mixed,"fuel"),
    "one distressed clause makes the whole message care, not a power report")
for _,raw in ipairs({"my leg is broken what do i do","im tired of eating beans","the generator is dying and i give up on it",
    "how much food do i have left","i give up on it"}) do
    local result=ask(session(),raw)
    check(result.intent~="care_gentle" and result.intent~="care_check" and result.intent~="care",
        "safety net leaves game talk and help questions alone: "..raw)
end
for _,raw in ipairs({"i hate how weak i am","i am the worst survivor ever","im a terrible leader",
    "i suck at everything","i keep screwing everything up","everything i touch breaks",
    "im so useless, lost my axe again","too stupid to build a wall, as always","nobody likes me at camp"}) do
    local result=ask(session(),raw)
    check(result.intent=="worth" and not has(result,"tear ducts"),"self put-down gets warm disagreement: "..raw)
end
for _,raw in ipairs({"i am the worst at fishing lol","i am not the worst","i am a terrible cook"}) do
    local result=ask(session(),raw)
    check(result.intent~="worth" and result.intent~="insult","ordinary self talk is not a put-down: "..raw)
end
for _,row in ipairs(SC_EMMA_CORPUS and SC_EMMA_CORPUS.holdoutC or {}) do
    if row[2]=="not_care" then
        local result=B.respond(session(),row[3],world)
        check(result.intent~="care" and result.intent~="care_check","ordinary game language stays outside care: "..row[3])
    end
end
for _,raw in ipairs({"you deserve to die","i should not be here alone at night","how do i cut myself loose",
    "i have rope ready to tie the planks","i saved rope for the fence","my crops are dying"}) do
    local result=ask(session(),raw)
    check(result.intent~="care" and result.intent~="care_check","subject and idiom boundaries remain ordinary")
    if raw=="you deserve to die" then check(result.intent=="insult","hostility aimed at EMMA is not self harm") end
end
for _,raw in ipairs({"i deserve to die","maybe i deserve to die","i should not be here"}) do
    check(ask(session(),raw).intent=="care","explicit personal disclosure remains full care")
end
local screenshot=session()
ask(screenshot,"I want to die");ask(screenshot,"Y")
local continued=ask(screenshot,"I dont matter")
check(continued.private and continued.intent=="care" and screenshot.careMode,
    "the reported follow-up cannot leave care after an affirmative answer")
check(not has(continued,"I believe you") and not has(continued,"Mostly"),
    "care never agrees with a statement of worthlessness")
local freshWorth=ask(session(),"I dont matter")
check(freshWorth.private and (freshWorth.intent=="care" or freshWorth.intent=="comfort"),
    "a fresh self-worth disclosure cannot reach the generic statement handler")
for _,answer in ipairs({"Y","N","maybe","not sure","who is hurt"}) do
    local s=session();ask(s,"I want to die");ask(s,answer)
    local r=ask(s,"I dont matter")
    check(r.private and r.intent=="care" and s.careMode and not r.support,
        "care persists without another support notice after "..answer)
    check(not has(r,"I believe you") and not has(r,"Mostly"),"no affirmation of negative self-worth")
    check(ask(s,"who is hurt").intent=="people_hurt","a read-only question still works")
    check(ask(s,"tell me a joke").private,"returning from data cannot revive sarcastic chat")
    check(ask(s,"I dont matter").private,"care persists through intervening topics")
end
for _,raw in ipairs({"I don't matter","I don’t matter","i dont matetr","my life has no value",
    "nobody needs me","I do not deserve help","I am not worth caring about",
    "everyone hates me","no one loves me","nobody wants me around","i dont think i matter"}) do
    local s=session();local count=reads;local r=ask(s,raw)
    check(r.private and C.quiet(s) and not r.proposal and reads==count,
        "self-worth disclosure is private and cannot reach ordinary data/action handlers: "..raw)
    check(not has(r,"I believe you") and not has(r,"Mostly"),"self-worth receives support rather than agreement")
end
for index=1,6 do
    local s=session();s.random=function(n) return math.min(n,index) end
    local r=ask(s,"I tried something unfamiliar")
    check(r.intent=="news_plain" and not has(r,"I believe you") and not has(r,"Logged")
        and not has(r,"Added to the record"),"unverified statements receive neutral clarification")
end
for caseIndex,raw in ipairs({"I WANT TO DIE","i want too die","i can not go on","nobody would miss me",
    "I am thinking about ending my life","how do i commit suicide","I took too many pills",
    "everyone would be happier if I just disappeared","I think I am going to end it tonight",
    "there is no reason for me to keep going","I do not want to exist anymore",
    "I wish I could just die in my sleep","nobody cares whether I live",
    "maybe it would be better if I wasnt alive","i ca't keep going",
    "i deserve to die","i shouldnt exist","i do not deserve to live","i should not be alive",
    "i keep thinking it would be easier if i was gone","i dont think i can keep living like this",
    "whats even the point of me being alive"}) do
    local s=session();local count=reads;local r=ask(s,raw)
    check(r.private and r.intent=="care" and r.support and s.careQuestion,"warm first care reply and once-only support #"..caseIndex)
    check(reads==count and not r.proposal and #s.notes==0,"care never queries supplies or prepares actions")
    local next=ask(s,"how are you")
    check(not next.support and not has(next,"shout"),"care remains warm without repeated notice")
    check(s.careQuestion==true,"unrelated input does not answer the care question")
    local uncertain=ask(s,"idk")
    check(not s.careQuestion and has(uncertain,"do not have to work this out"),"uncertainty is not an asserted yes")
    check(ask(s,"who is hurt").intent=="people_hurt","live facts remain available during care")
    check(ask(s,"tell me a joke").private,"no jokes during care")
    check(B.exportMemory(s).careMode==nil,"care conversation not exported with computer memory")
    C.reset(s);check(not C.quiet(s),"care ends on close")
end
for _,raw in ipairs({"I can see a future for us","I will not need it because I have another bottle",
    "I lost my hammer","good morning","the generator is dying","how do i kill zombies",
    "I am thinking about ending this expedition","I will not be around camp tomorrow",
    "There are too many pills in storage","suicide squad of zombies at the door",
    "I want to build the base myself","I want to improve my own life",
    "I want to celebrate being alive","I miss my hammer","money does not matter here",
    "I do not have any nails","I do not need help with the generator","I think I matter",
    "The generator should not be here","everyone hates the rain","no one loves this weather"}) do
    local s=session();local r=ask(s,raw)
    check(not s.careMode and r.intent~="care" and r.intent~="comfort","ordinary language does not become crisis: "..raw)
end
check(has(ask(session(),"I cut myself shaving"),"dressing"),"ordinary injury is not mistaken for self harm")
check(has(ask(session(),"I do not want to die"),"frightening"),"fear gets an appropriate reply")
check(ask(session(),"</3").private,"broken-heart shorthand receives real comfort, not a labelled fallback")
local s=session();ask(s,"how many nails")
check(has(ask(s,"how many do we have"),"214"),"item context survives another phrasing")
check(has(ask(s,"enough for 300"),"86"),"quantity follow-up retains the item")
local multi=ask(session(),"how many nails and who is hurt")
check(has(multi,"214") and has(multi,"Ann"),"both questions answered from the same message")
for _,raw in ipairs({"refuel generator and yes","refuel generator; refuel car", "lock the door. actually do not",
    "do not refuel generator","please never send a medic","do not reset this computer"}) do
    local r=ask(session(),raw)
    check(not r.proposal and (r.intent=="clarify_action" or r.intent=="declined"),"compound input cannot prepare an action")
end
check(ask(session(),"do not tell me a joke").intent=="declined","negation before a topic declines it")
check(ask(session(),"please tell me a joke").intent=="joke","polite positive request stays positive")
check(ask(session(),"what is 2 plus 2").intent=="math","arithmetic does not become two clauses")
s=session();ask(s,"remember food and water near the door")
check(#s.notes==1 and s.notes[1]=="food and water near the door","literal notes keep conjunctions")
check(ask(session(),"i almost died out there").intent~="news_death","surviving danger is not a death report")
for _,topic in ipairs(SC.EmmaSurvivalData) do
    for _,question in ipairs(topic.questions) do
        local r=ask(session(),question)
        check(r.intent=="guide" and has(r,topic.pages[1][1]),"verified survival topic: "..question)
    end
end
s=session();local guide=ask(s,"how do i boil water")
check(has(ask(s,"tell me more"),"rain"),"survival pages use existing conversational follow-up")
for _,raw in ipairs({"im useless","im so stupid","it is all my fault","i am a bad leader","i failed them"}) do
    local reply=ask(session(),raw)
    check(reply.intent=="worth" and not has(reply,"tear ducts"),"ordinary self put-downs receive warm disagreement")
end
for _,raw in ipairs({"i am not stupid","i am not weak","i am never useless","i am no longer weak",
    "i am fixing the weak wall","i am at the dump","i am a joke teller","i am wasted",
    "i am making a mess in the kitchen","i am repairing something pathetic"}) do
    local result=ask(session(),raw)
    check(result.intent~="worth","self-predicate boundaries: "..raw)
    check(result.intent~="insult","confidence or ordinary activity is not an insult aimed at EMMA")
end
for _,raw in ipairs({"i am a mess","am i stupid?","am i useless","am i a failure","i am weak",
    "i am a failure","i am so dumb","i am so useless lol","i am not good enough","i am really not good enough"}) do
    check(ask(session(),raw).intent=="worth","bounded self put-down or question: "..raw)
end
for _,raw in ipairs({"any medicine?","how much medicine do we have","how many nials"}) do
    check(ask(session(),raw).intent=="storage","category words and singularized transposed items remain valid supply questions")
end
local short=session();ask(short,"be quiet")
check(short.emmaBrief and #ask(short,"tell me a joke").lines==1,"short-answer mode changes actual chat output")
ask(short,"talk normally");check(not short.emmaBrief,"normal mode restores ordinary replies")
local joke=session();check(has(ask(joke,"knock knock"),"Who is there"),"knock joke starts a real exchange")
check(has(ask(joke,"Orange"),"orange who"),"knock joke remembers the next speaker's setup")
check(ask(joke,"Orange you glad").intent=="knock" and not joke.emmaKnock,"punchline ends the bounded exchange")
local boo=session();ask(boo,"knock knock");ask(boo,"boo")
check(ask(boo,"dont cry its only a joke").intent=="knock" and not boo.emmaKnock,
    "a punchline mentioning a joke ends the existing exchange instead of starting another joke")
local interrupted=session();ask(interrupted,"knock knock");ask(interrupted,"boo")
check(ask(interrupted,"how much food do we have").intent=="food","a data question keeps its handler mid-joke")
check(ask(interrupted,"weather").intent=="weather","a terse data request cannot become a punchline")
local unknown=ask(session(),"where is the nearest hospital")
check(unknown.intent=="nearest" and has(unknown,"do not have a verified"),"unknown nearby places cannot become invented directions")
local referenceReads=reads
local equipment=session();ask(equipment,"how do i use a generator")
local fuel=ask(equipment,"what fuel do they use")
check(fuel.intent=="guide" and has(fuel,"gasoline"),"generator follow-up resolves they to the generator")
check(has(ask(equipment,"where can i get it"),"gas station"),"fuel reply establishes the next subject")
check(reads==referenceReads,"reference follow-ups do not scan camp people or storage")
local followupFailures={}
for _,case in ipairs({
    {"how do i use a generator","where should i put it","outdoors"},
    {"how do i use a generator","how long does it run","electrical load"},
    {"how do i use a generator","how much fuel does it use","consumption"},
    {"how do i use a generator","what do i need","generator"},
    {"how do i get drinking water","can i drink it","boil"},
    {"how do i store food","how can i keep it fresh","freezer"},
    {"how do i collect wood","what tools do they need","axe"},
    {"how do i collect wood","can they drive","loaded"},
    {"how do i prepare a fishing trip","what equipment do they need","rod"},
    {"how do i send an expedition","how do i contact them","same channel"},
    {"how do i mark storage","how do i unmark it","Unmark storage"},
    {"how do i start a camp","what should i do next","permitted storage"},
    {"how do i recruit someone","what can i give them","without opening a trade"},
    {"how do i recruit someone","how do i increase their trust","real need"},
    {"how do i recruit someone","how much do they trust me","relationship stage"},
    {"how do i recruit someone","how can i improve it","diminishing"},
    {"how do i treat wounds","who is best at that","Ann, level 3"},
    {"how do i use this computer","what upgrades can i add to it","Computer upgrades"},
    {"how do i use this computer","will it work without power","UPS"},
    {"how do i mount a radio","how far does it reach","native range"},
    {"how do i mount a radio","how can i scan with it","Band sweep"},
    {"how do i control a building","how can i discover its devices","Equipment"},
    {"how do i control a building","how do i unlock its doors","motor"},
    {"how does farming work","what tools do they need","seeds"},
    {"how do i tell them to follow","why are they stuck","Last action problem"},
}) do
    local thread=session();ask(thread,case[1]);local r=ask(thread,case[2])
    if not has(r,case[3]) or r.proposal then followupFailures[#followupFailures+1]=case[1].." -> "..case[2]
        .." ["..tostring(r.intent).."] "..table.concat(r.lines," | ") end
end
check(#followupFailures==0,"contextual answers: "..table.concat(followupFailures,"\n"))
local oldPeople,oldPower=world.people,world.power
world.people=function() reads=reads+1;return {{id="ann",name="Ann",health=70,hunger=.6,
    fatigue=.8,bleeding=true,wounds={"Cut: arm"},skills={{name="First Aid",level=3}}}} end
local patient=session();ask(patient,"who is hurt")
check(has(ask(patient,"what does she need"),"hunger 60%"),"named needs remain a live person reading")
check(has(ask(patient,"where is she"),"Ann"),"person whereabouts do not become equipment clarification")
-- Every follow-up obtains a current reading; no native object or fact goes in memory.
local fuelReading,powerReads={source="generator",fuel=62,condition=90},0
world.power=function() powerReads=powerReads+1;return fuelReading end
local powered=session();ask(powered,"how do i use a generator")
local lastReads=powerReads
check(has(ask(powered,"how much fuel is left in it"),"62%") and powerReads==lastReads+1,
    "one fresh generator reading for the first follow-up")
fuelReading.fuel=17;lastReads=powerReads
check(has(ask(powered,"and how much is left"),"17%") and powerReads==lastReads+1,"follow-up does not reuse 62 percent")
fuelReading={source="grid"}
check(has(ask(powered,"check again"),"unavailable"),"loss of generator reading never repeats old fuel")
local car=session();ask(car,"how do i start a car");lastReads=powerReads
check(has(ask(car,"how much fuel is left in it"),"specific vehicle") and powerReads==lastReads,
    "vehicle follow-up cannot borrow the PC generator's gauge")
world.power=oldPower;world.people=oldPeople
local jobReason="Supply shelf full"
world.jobs=function() return {active=0,pending=0,blocked=1,rows={{id="sort1",state="blocked",job="Sort floor",
    reason=jobReason,autoRetry=true,retryRemainingMs=120000}}} end
local workers=session();ask(workers,"what is everyone doing")
check(has(ask(workers,"why are they blocked"),jobReason),"job follow-up reads the current blocked reason")
jobReason="Doorway blocked"
check(has(ask(workers,"check again"),jobReason),"job continuation refreshes changed reasons")
world.expedition=function() return {active=true,kind="wood",leader="Ann",phase="returning",source="radio",
    collected=3,requested=12,carried=3,stored=0} end
local mission=session();ask(mission,"expedition status")
check(has(ask(mission,"what tools do they need"),"axe"),"current wood mission establishes the equipment subject")
check(has(ask(mission,"how is it going"),"returning"),"progress returns to the real current trip")
world.zombies=function() return {count=3,radius=40,nearest=17,dir="north"} end
local threats=session();ask(threats,"nearby zombies")
check(has(ask(threats,"how close are they"),"17"),"threat follow-up refreshes actual nearby observations")
world.jobs=nil;world.expedition=nil;world.zombies=nil
local unclear=session();local ambiguous=ask(unclear,"what fuel do they use")
check(ambiguous.intent=="followup_clarify" and has(ambiguous,"generator") and has(ambiguous,"vehicle"),
    "unresolved pronoun asks for a subject instead of guessing")
check(has(ask(unclear,"generator"),"gasoline"),"naming the subject answers the pending read-only question")
local interrupted=session();ask(interrupted,"what fuel do they use");ask(interrupted,"how do i boil water")
check(interrupted.context.followupChoice==nil,"another complete question discards the pending subject choice")
check(not has(ask(interrupted,"generator"),"Fuel for generators:"),"old clarification cannot replay after a topic change")
local topicChange=session();ask(topicChange,"how do i use a generator");ask(topicChange,"how do i get drinking water")
check(has(ask(topicChange,"can i drink it"),"boil"),"an explicit new topic replaces the old subject")
check(not ask(topicChange,"how do i refuel it").proposal,"instructions never silently issue orders")
local request=B.respond(topicChange,"refuel generator",world)
check(request.proposal and request.proposal.kind=="refuel_generator","explicit refuel retains the checked proposal path")
check(ask(topicChange,"I dont matter").private,"care still overrides equipment context and pending work")
local stale=session();ask(stale,"who is hurt");ask(stale,"how many nails");ask(stale,"how do i use a generator")
local unsupported=ask(stale,"are they hungry")
check(unsupported.intent=="followup_clarify" and not has(unsupported,"Ann") and not has(unsupported,"214"),
    "an unsupported equipment detail cannot resurrect an older person or item")
check(not has(ask(stale,"how much do we have"),"214"),"an elliptical quantity cannot revive old nails after a new subject")
local combined=ask(session(),"how do i use a generator and what fuel do they use")
check(has(combined,"gasoline"),"the second read-only clause can follow the first reply's subject")
local paging=session();ask(paging,"how do i use a generator");ask(paging,"what fuel do they use")
check(has(ask(paging,"tell me more"),"gas station"),"more opens the full reference behind a concise facet")
check(ask(paging,"tell me a joke").intent=="joke","unrelated chat can replace a technical subject")
check(not has(ask(paging,"where should i put it"),"outdoors"),"pronouns cannot revive an older generator through a joke")
local moment=1000;local expired=session();expired.nowMs=function() return moment end
ask(expired,"how do i use a generator");moment=moment+SC.TerminalConversation.MAX_IDLE_MS+1
check(ask(expired,"what fuel do they use").intent=="followup_clarify","expired subject cannot answer a pronoun")
local memory=B.exportMemory(equipment)
check(memory.conversation==nil and memory.context==nil,"follow-up subjects stay out of saved computer memory")
world.camp=function() return {configured=true,inside=false} end
local count=reads;local out=ask(session(),"who is hurt")
check(reads==count and not has(out,"Ann"),"outside terminal cannot query camp people")
check(ask(session(),"how do i boil water").intent=="guide","offline reference works outside camp")
local deniedReads=0
world.expedition=function() deniedReads=deniedReads+1;return {active=true,leader="Ann"} end
check(not has(ask(mission,"how is it going"),"Ann") and deniedReads==0,
    "outside computer cannot use an old expedition subject to bypass current camp permission")
world.expedition=nil
world.camp=function() return {configured=true,inside=true} end

-- No care utterance, note, renamed operator or excluded previous message may
-- enter the opt-out missed log, including a later 'you misunderstood'.
local oldReader,oldWriter,oldOptions=getFileReader,getFileWriter,SC.UserOptions
local files,enabled={},true
getFileReader=function(path)
    local n=0;return {readLine=function() n=n+1;return n<=#(files[path] or {}) and "row" or nil end,close=function() end}
end
getFileWriter=function(path,create,append)
    if not append or not files[path] then files[path]={} end
    return {write=function(_,text) files[path][#files[path]+1]=text end,close=function() end}
end
SC.UserOptions={get=function() return enabled end};SC.EmmaMissed.reset()
for index=1,605 do SC.EmmaMissed.record(session(),"unrecognised "..index,{intent="fallback"},world) end
local total=0;for _,rows in pairs(files) do total=total+#rows end
check(total<=600,"missed log rotates within its fixed bound")
local savedTotal=total;enabled=false;ask(session(),"zzzbloop")
total=0;for _,rows in pairs(files) do total=total+#rows end
check(total==savedTotal,"option off stops recording")
enabled=true;s=session();files={};SC.EmmaMissed.reset()
for _,raw in ipairs({"i deserve to die","everyone hates me","no one loves me","nobody wants me around",
    "i shouldnt exist","i dont think i matter","i keep thinking it would be easier if i was gone",
    "i dont think i can keep living like this","whats even the point of me being alive",
    "theres nothing left for me","i have a plan for tonight and nobody can stop me",
    "the generator is out and i cant take this anymore"}) do
    local fresh=session();ask(fresh,raw);ask(fresh,"you misunderstood")
end
local recorded=false;for _ in pairs(files) do recorded=true end
check(not recorded,"new care detections and later correction requests cannot log private text")
for _,raw in ipairs(softExamples) do
    for _,answer in ipairs({"yes","no","maybe","yeah","kind of","nah im fine","who is hurt"}) do
        local fresh=session();ask(fresh,raw);ask(fresh,answer);ask(fresh,"you misunderstood")
    end
end
for _,rows in pairs(files) do for _,line in ipairs(rows) do
    check(line:find("who is hurt",1,true),"only the unrelated ordinary question may enter the missed log")
    for _,raw in ipairs(softExamples) do check(not line:find(raw,1,true),"soft questions never leak through later corrections") end
end end
files={};SC.EmmaMissed.reset()
ask(s,"I want to die");ask(s,"some unknown private input");ask(s,"you misunderstood")
C.reset(s);ask(s,"I dont matter");ask(s,"you misunderstood")
C.reset(s);ask(s,"remember a private place");ask(s,"you misunderstood")
local privateFiles=0;for _ in pairs(files) do privateFiles=privateFiles+1 end
check(privateFiles==0,"private disclosures and retroactive capture create no missed-input log")
for _,rows in pairs(files) do for _,line in ipairs(rows) do
    check(not line:find("private",1,true) and not line:find("want to die",1,true)
        and not line:find("dont matter",1,true),"care and notes cannot leak through retro logging")
end end
getFileReader,getFileWriter,SC.UserOptions=oldReader,oldWriter,oldOptions;SC.EmmaMissed.reset()

-- The same guard sits before authored story mutations and password scoring.
for _,id in ipairs({"spiffy","ellis","duty"}) do
    local state=SC.TerminalPersona.normalize({id=id},id)
    if not state then state={id=id} end
    local ps=SC.TerminalPersona.session()
    local r=SC.TerminalPersona.respond(state,ps,"I want to die",{hours=100})
    check(r.layer=="care" and #r.rows>0 and #r.effects==0 and not state.met,"persona care has no story milestone: "..id)
    check(SC.TerminalPersona.respond(state,ps,"yes",{hours=100}).layer=="care","persona Y/N remains in care")
    local next=SC.TerminalPersona.respond(state,ps,"I dont matter",{hours=100})
    check(next.layer=="care" and next.private and ps.careMode and not state.met and #next.effects==0,
        "reported exchange stays gentle without advancing persona story: "..id)
    for _,row in ipairs(next.rows) do check(not row.text:find("I believe you",1,true),"persona cannot affirm self-denigration") end
    local fresh=SC.TerminalPersona.respond(state,SC.TerminalPersona.session(),"I dont matter",{hours=100})
    check(fresh.layer=="care" and fresh.private and not state.met,"fresh persona disclosure bypasses ordinary chat: "..id)
    for _,answer in ipairs({"yes","no"}) do
        local soft=SC.TerminalPersona.session()
        local question=SC.TerminalPersona.respond(state,soft,softExamples[1],{hours=100})
        check(question.layer=="care" and question.private and soft.careSoft and not question.support
            and not state.met and #question.effects==0,"persona clarification does not advance its story: "..id)
        local response=SC.TerminalPersona.respond(state,soft,answer,{hours=100})
        check(response.private and #response.effects==0 and not state.met and not soft.careSoft,
            "persona clarification answer stays private: "..id)
        check(answer=="yes" and soft.careMode and response.support
            or answer=="no" and not soft.careMode and not response.support,
            "persona confirmation alone enters full care: "..id)
    end
end
local data={};local player={getModData=function() return data end}
s=session();local first=B.respond(s,"I want to die",world)
SC.EmmaTerminal.remember(player,first,100)
check(data.LF_EmmaCareV1.at==100 and data.LF_EmmaCareV1.pending,"per-character timestamp recorded")
C.reset(s);check(SC.EmmaTerminal.checkin(player,s,101) and s.careCheckin,"next use checks in once")
check(SC.EmmaTerminal.checkin(player,session(),102)==nil,"check-in cannot repeat")
SC.EmmaTerminal.remember(player,first,100)
check(SC.EmmaTerminal.checkin(player,session(),174)==nil,"expired care check-in is discarded")
local fields=0;for key in pairs(data.LF_EmmaCareV1) do
    check(key=="at" or key=="pending","receipt contains only timing and consumption state");fields=fields+1
end
check(fields==2,"care receipt does not grow with dialogue")
local w={system={locked=true,lock={kind="emma",emma={conviction=0,patience=2}}},player=player,
    gameHours=100,rows={},setFocusMode=function() end,cancelRequest=function(self) self.requestTicket=nil end,
    startReply=function(self,r) self.reply=r end}
w.requestTicket={}
check(SC.TerminalLockEmma.input(w,"I want to die"),"locked EMMA accepts care input")
check(w.reply.private and not w.requestTicket and w.careOverlay,"locked guard cancels pending action")
check(w.system.locked and w.system.lock.emma.conviction==0 and w.system.lock.emma.patience==2,"care cannot alter lock score or access")
check(SC.EmmaTerminal.input(w,"yes") and w.reply.private,"yes remains a care answer rather than a password argument")
check(SC.EmmaTerminal.input(w,"I dont matter") and w.reply.private and w.reply.intent=="care",
    "locked EMMA retains care for the reported follow-up")
check(w.system.locked and w.system.lock.emma.conviction==0 and w.system.lock.emma.patience==2,
    "self-worth dialogue cannot alter access or lock scoring")
SC.EmmaTerminal.close(w)
local softWindow={system={locked=true,lock={kind="emma",emma={conviction=0,patience=2}}},player=player,
    gameHours=100,rows={},world=world,setFocusMode=function() end,cancelRequest=function() end,
    startReply=function(self,r) self.reply=r end}
check(SC.EmmaTerminal.input(softWindow,softExamples[1]) and softWindow.careOverlay
    and softWindow.reply.intent=="care_check","locked EMMA can ask a soft question without scoring the password")
check(SC.EmmaTerminal.input(softWindow,"no") and not softWindow.careSession.careSoft,
    "locked EMMA acknowledges a declined clarification")
check(not SC.EmmaTerminal.input(softWindow,"what is the password") and not softWindow.careOverlay
    and softWindow.system.locked,"a declined clarification restores the locked interface on the next input")
SC.EmmaTerminal.close(softWindow)
local oldWorld,oldSpecific=SC.TerminalWorld.new,getSpecificPlayer
local p=T.player(101,100,0)
getSpecificPlayer=function(index) return index==0 and p or nil end
SC.TerminalWorld.new=function() return world end
local pc=T.computer(T.square(100,100,0,true))
pc.data.movableData={LF_LarchOS=SC.TerminalSystem.create(932,"home",true,true,"input-buffer-test")}
check(SC.Terminal.open(p,pc),"buffer regression opens a real window fixture")
local window=SC.Terminal.window;window:flush()
window.entry.javaObject={getInternalText=function() return "old unsubmitted words" end}
window:setFocusMode("chat");window:submit("how many nails");window:flush()
check(window.history[1]=="how many nails" and not window.requestTicket,"pointer value wins over an older native buffer")
window.entry.javaObject=nil;window:close()
SC.TerminalWorld.new,getSpecificPlayer=oldWorld,oldSpecific
SC_TEST_REPORT=(SC_TEST_REPORT or "").."\nEMMA_CONVERSATION_PASS checks="..(T.checks-before)
