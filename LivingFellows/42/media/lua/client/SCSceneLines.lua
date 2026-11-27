-- SPDX-License-Identifier: MIT
-- Complete authored turns. Branches answer the same subject as their opener.
-- Factful packets name their evidence; all other cards express a preference,
-- question or present feeling rather than inventing an adventure.
LivingFellows = LivingFellows or {}
local SC = LivingFellows
local L = { cards = {}, byId = {}, arguments = {}, aftermath = {}, catalogs = {} }
SC.SceneLines = L
local tags = { "agree", "tease", "pushback", "comfort", "deflect" }
local function pool(card, phase, lines, requires, asserts)
    local topic = "scene." .. card.id .. "." .. phase
    local variants = {}
    for n, value in ipairs(lines) do
        local text = type(value) == "table" and value[1] or value
        variants[#variants + 1] = { id = tostring(n), text = text,
            clean = type(value) == "table" and value.clean or text }
    end
    local packets = {{ id = topic, scene = topic, ideaId = topic, shape = phase,
        voiceWeights = { common = 1 }, requires = requires or {}, asserts = asserts or {},
        variants = variants }}
    card[phase] = { topic = topic, packets = packets }
    L.catalogs[#L.catalogs + 1] = packets
    if SC.Dialogue then
        local display = {}
        for _, row in ipairs(variants) do display[#display + 1] = { row.text, clean = row.clean } end
        SC.Dialogue.register(topic, { common = display })
    end
end
local function card(id, kind, open, replies, follows, close, requires, asserts)
    local result = { id = id, kind = kind }
    pool(result, "open", open, requires, asserts)
    for _, tag in ipairs(tags) do
        if replies[tag] then pool(result, "reply_" .. tag, replies[tag], requires, asserts) end
        if follows[tag] then pool(result, "follow_" .. tag, follows[tag], requires, asserts) end
    end
    pool(result, "close", close, requires, asserts)
    L.cards[#L.cards + 1] = result
    L.byId[id]=result
    return result
end

card("route", "plans", {
    "I'd rather take the long road home than argue with a short one full of teeth.",
    "Next time we go out, I want an exit picked before an entrance.",
    "A map ought to have a little mark for places we can afford to leave alone.",
    "If a road looks too easy, I'd like somebody to tell me why." }, {
    agree={"Agreed. Coming home belongs in the plan.","A way back first. Then we can talk about the rest."},
    tease={"You make a walk sound like a bank job.","Should we ask the road for references?"},
    pushback={"The long way has blind corners too. I'd want a look at both.","An exit on paper isn't an exit if the road is blocked."},
    comfort={"We can slow down and check it together.","You won't have to watch every turning alone."},
    deflect={"Can we pick the road after we've sat down a while?","My feet would like a vote before the map does."} }, {
    agree={"Good. Distance is cheaper than a funeral.","Then we agree on what counts as a successful trip."},
    tease={"A bank job has better opening hours.","If the road answers, you can do the talking."},
    pushback={"Fair. Two routes, and neither gets our blind trust.","Then we look before we commit. That's all I'm asking."},
    comfort={"I'd appreciate another pair of eyes.","All right. Together sounds manageable."},
    deflect={"Your feet can chair the meeting after a rest.","Fine. No route decisions on sore feet."} }, {
    "Keep the map handy. We can settle the details before we leave.",
    "A plan with room to turn back. I can live with that.",
    "Nobody wins a prize for taking the worst road." })

card("food", "plans", {
    "I'd like the food put where a hungry person can find it without a search party.",
    "We ought to agree which food is for tonight and which is for a bad week.",
    "A shelf label might save us an argument over dinner.",
    "I'd feel better if supper and the reserve weren't the same pile." }, {
    agree={"Mark the reserve clearly. Nobody should have to guess.","A little order would help us share it fairly."},
    tease={"You want a restaurant or a filing cabinet?","Should the beans sign themselves out?"},
    pushback={"Labels won't help if only one person decides the portions.","Leave room for people who need more after hard work."},
    comfort={"We can sort it together. You don't have to count every tin alone.","We'll make a plan everyone can understand."},
    deflect={"Could the discussion include something to eat?","I'm willing to debate this after supper."} }, {
    agree={"Exactly. Less guessing, fewer hurt feelings.","Then we can save our arguments for something worth one."},
    tease={"A filing cabinet with edible contents would do.","Only if the beans can hold a pencil."},
    pushback={"Fair point. We agree on the portions together.","Needs first, then labels. I can work with that."},
    comfort={"Thanks. I get tired of turning every meal into sums.","That would take a weight off."},
    deflect={"Supper first. The committee can chew quietly.","Fine. A fed audience might be kinder."} }, {
    "Keep a reserve, share the rest, and tell people where it is.",
    "A clear shelf would be a fine start.",
    "Nobody ought to feel like a thief for needing supper." })

card("winter", "plans", {
    "I'd rather think about cold weather while I can still feel my fingers.",
    "We should make a list for winter before winter starts making demands.",
    "Dry blankets deserve a place in the plan, beside food and water.",
    "I keep thinking about how we'd stay warm if this place got colder." }, {
    agree={"Dry clothes, dry bedding, somewhere sheltered. Start there.","Better to make the list now than shiver through it later."},
    tease={"Planning to send winter a strongly worded letter?","I suppose the snow won't accept an apology."},
    pushback={"We still have today's needs. We can't put everything aside for winter.","A list isn't insulation. We should pick one job we can finish."},
    comfort={"We'll work through it a little at a time.","There are enough hands here to help with the preparations."},
    deflect={"Can we think about one season at a time for a minute?","I'd like a quiet evening before the weather meeting."} }, {
    agree={"Exactly. Ordinary things, ready before we need them.","A dull list would be a comforting list."},
    tease={"I'll underline the part about being unreasonable.","Then we'd better offer it a blanket."},
    pushback={"One finished job beats ten worries. Fair enough.","Today first, with a little put aside for tomorrow."},
    comfort={"A little at a time sounds better than all at once.","Good. I needed to hear the word 'we'."},
    deflect={"All right. The list can wait until morning.","Quiet evening approved. Weather adjourned."} }, {
    "Dry things first. We can manage one shelf at a time.",
    "Nobody needs to solve a whole winter tonight.",
    "Write it down before worry adds another dozen items." })

card("visitors", "plans", {
    "If somebody comes asking for help, I'd like us to have agreed on an answer.",
    "We need a way to meet strangers that doesn't begin with everyone shouting.",
    "Kindness is easier when we know where we're asking visitors to stand.",
    "What do we tell somebody who wants to trade and stay the night?" }, {
    agree={"One person speaks. The rest watch without crowding them.","We can be careful without being cruel."},
    tease={"A reception desk might be ambitious.","Should we issue little paper numbers?"},
    pushback={"A friendly voice doesn't tell us what they're carrying.","I want a clear distance and an open way out for both sides."},
    comfort={"We'll decide together. Nobody has to judge a stranger alone.","Wanting to help is a good start. We can give it some boundaries."},
    deflect={"Let's work out the first hello before we offer a bed.","Trade first. Sleeping arrangements can wait."} }, {
    agree={"That's the balance I was trying to find.","Careful and decent. I'd like us to manage both."},
    tease={"Only if the desk has a good view of the road.","Number one: please don't bite the receptionist."},
    pushback={"Yes. Space for them and space for us.","Then we keep the greeting calm and the precautions plain."},
    comfort={"Thank you. It's a hard thing to decide on the spot.","Boundaries would help. Guessing doesn't."},
    deflect={"A calm hello first. That sounds sensible.","All right. One decision at a time."} }, {
    "Clear rules are kinder than a surprise at the gate.",
    "We can leave room for a stranger to be frightened too.",
    "Tell everyone the same plan before somebody knocks." })

card("water", "plans", {
    "I'd like our drinking water kept where nobody can mistake it for wash water.",
    "We should agree how much water stays in reserve.",
    "An empty container is a useful reminder. I'd rather not collect reminders.",
    "Can we put the water plan somewhere other than inside one person's head?" }, {
    agree={"Label the containers and keep the drinking supply separate.","A shared plan is safer than somebody's memory."},
    tease={"Your containers are getting more organised than I am.","Will there be a test on which bucket is which?"},
    pushback={"Reserve some for cleaning too. Dirty hands cost us plenty.","We need a way to replace it, as well as a place to keep it."},
    comfort={"I'll help mark them. It's a small job we can finish.","You don't have to carry the whole worry yourself."},
    deflect={"First let me remember where I put my cup.","Could we hold the meeting near a drink?"} }, {
    agree={"Good. Clear labels and no heroic guessing.","Then anyone can spot a shortage in time."},
    tease={"Only the advanced bucket course has an exam.","The containers have fewer bad habits."},
    pushback={"Right. Drinking, washing, and a way to refill both.","That's a fair addition. Write it beside the reserve."},
    comfort={"Thanks. A finished small job would feel good.","I'd welcome the help."},
    deflect={"Find the cup. We'll start with the practical demonstration.","Near a drink is an excellent location."} }, {
    "Clear water, clear labels. Two kinds of reassurance.",
    "Make the plan simple enough to use when we're tired.",
    "Better to ask twice than drink from the wrong container." })

card("watch", "plans", {
    "I'd like us to agree how to hand over a watch without waking the whole place.",
    "We should have a quiet signal for 'come and look at this'.",
    "Nobody ought to guess whether the next person heard the handover.",
    "A watch is easier if you know exactly who takes over." }, {
    agree={"Say the name, wait for an answer, then finish the handover.","A clear answer matters more than a loud one."},
    tease={"I vote against a trumpet.","We could appoint a deputy for the deputy."},
    pushback={"A signal needs a meaning everyone knows. No clever improvising.","And a tired person should be allowed to say they're too tired."},
    comfort={"We can keep the handover simple. Nobody has to do it perfectly.","We'll help each other stay awake when it's difficult."},
    deflect={"Can we practise the quiet part right now?","I'd like to discuss sleep by having some."} }, {
    agree={"Exactly. Heard and answered, then off your feet.","Good. No handover to somebody's snoring."},
    tease={"The trumpet proposal is unanimously dead.","Only if the deputy knows when to let people sleep."},
    pushback={"Agreed. No shame in asking for relief.","Plain meanings. We can save clever for daylight."},
    comfort={"Simple would be a relief.","Thanks. Being tired isn't improved by being alone."},
    deflect={"Practice begins now. Meeting nearly over.","An excellent suggestion from the sleep committee."} }, {
    "Make sure the next person answers. That's the rule.",
    "Quiet, clear, and nobody left wondering.",
    "A short plan might earn us a longer rest." })

card("camp_name", "joke", {
    "If this camp needs a name, I suggest Something Else To Repair.",
    "We could name the place after its most reliable feature: Work To Be Done.",
    "I'd like a camp name that doesn't make a promise the roof can't keep.",
    "Every respectable establishment needs a sign. Ours could say 'Trying'." }, {
    agree={"Trying is honest. Honesty saves paint.","Work To Be Done would age well."},
    tease={"Put your name underneath. Management should take credit.","How about the Grand Hotel Almost?"},
    pushback={"Let's keep it off a sign strangers can see from the road.","A name's fine. Advertising it isn't."},
    comfort={"Whatever we call it, I'd like it to feel like somewhere we belong.","Trying is enough for a start."},
    deflect={"I refuse to attend a naming ceremony before supper.","Can we name the chairs first? I'm fond of this one."} }, {
    agree={"Then it's settled until something better needs painting.","A name with room for improvement."},
    tease={"Management regrets that the complaints desk is also broken.","Almost has vacancies. Mostly in the roof."},
    pushback={"Private joke, then. No roadside attractions.","Fair. The sign can live in our heads."},
    comfort={"I'd settle for belonging before branding.","Yes. A home can start with trying."},
    deflect={"Ceremony postponed on account of hunger.","That chair will let the fame go to its legs."} }, {
    "Whatever the name, wipe your boots before coming in.",
    "Put the paint away. We've founded enough things for one evening.",
    "I'd stay somewhere called Trying. Expectations would be manageable." })

card("luxury", "joke", {
    "My idea of luxury is a sock with no opinion about my toes.",
    "If we ever get a catalogue again, I'm ordering one ordinary quiet morning.",
    "I miss the sort of complaint you could fix by asking for a manager.",
    "When this is over, I want a chair selected for comfort rather than availability." }, {
    agree={"A small ordinary thing would feel extravagant now.","Put me down for something boring and comfortable."},
    tease={"A quiet morning? Somebody's getting above their station.","Comfortable furniture. Listen to the aristocracy."},
    pushback={"Don't spend all evening waiting for after. We still need a little comfort now.","Keep one small good thing for today too."},
    comfort={"You deserve a little ordinary comfort.","I hope you get it. I'd like to see you properly rested."},
    deflect={"I'll settle for a meal without standing up.","Can the catalogue supply another blanket?"} }, {
    agree={"Boring. That's exactly the luxury I'm after.","Nothing dramatic, with a very soft cushion."},
    tease={"I'll remember the common people when I have my chair.","Next I'll demand matching socks. Absolute decadence."},
    pushback={"Fair. A small comfort now is still a comfort.","All right. Today gets a place on the list."},
    comfort={"Thank you. I'd like that for all of us.","A proper rest sounds almost unreal."},
    deflect={"A blanket goes on the first page.","Seated dinner. Another ambitious demand approved."} }, {
    "Keep the list. We ought to remember what ordinary felt like.",
    "Luxury can begin with getting off our feet.",
    "Small comforts still count." })

card("committee", "joke", {
    "I nominate this silence for chair of the next meeting.",
    "We could solve everything by forming a committee. Then we'd have two problems.",
    "If anyone writes minutes of this conversation, leave out the sensible parts.",
    "I'd like to propose a motion that we stop proposing motions." }, {
    agree={"Motion carried. Discussion has exhausted its supplies.","A short meeting is a rare public service."},
    tease={"Your proposal will need three copies and a better chair.","I appoint you deputy assistant to the silence."},
    pushback={"Some things do need agreeing on. Just keep the speeches short.","A little order isn't the enemy. Endless talking is."},
    comfort={"We can stop talking for a while. Nobody will mind.","You look as though a quiet minute would help."},
    deflect={"I abstain. It takes less effort.","Wake me when the vote reaches supper."} }, {
    agree={"Excellent. Democracy has earned a sit down.","Then the silence may assume office."},
    tease={"I resign before the stationery arrives.","Deputy silence is a demanding position."},
    pushback={"Fair. Useful decisions, very short speeches.","Then we're agreed on the part that matters."},
    comfort={"I'd take that quiet minute, thanks.","Good. I was running out of words worth hearing."},
    deflect={"Your abstention has been quietly noted.","Supper has an excellent chance in the voting."} }, {
    "Meeting closed. Please leave the chairs where people can use them.",
    "For once, nobody needs the last word.",
    "I'll second the quiet." })

card("boots", "joke", {
    "I think my boots have started making decisions without me.",
    "A good pair of boots is just a house you carry below the knees.",
    "If these boots could talk, they'd ask for separate accommodation.",
    "I owe my feet an apology. I'd like somebody else to deliver it." }, {
    agree={"Feet do a lot of work for very little gratitude.","A dry pair of socks can change an entire evening."},
    tease={"Your boots have always shown better judgement.","Maybe they want a walking partner with fewer complaints."},
    pushback={"Look after them before a small sore becomes a real problem.","Jokes aside, don't ignore sore feet."},
    comfort={"Take the weight off them for a while.","Rest them. Nobody needs you standing for this conversation."},
    deflect={"Let's discuss this from separate ends of the room.","I was enjoying the air before footwear entered the conversation."} }, {
    agree={"Exactly. A little gratitude, and no more puddles.","Dry socks belong in the constitution."},
    tease={"Their judgement keeps getting us into puddles.","Then they can carry their own pack."},
    pushback={"Fair. I'll give them a proper look.","All right. Complaint received by management."},
    comfort={"That's the best offer I've had all evening.","Thanks. Sitting makes my argument much stronger."},
    deflect={"Separate ends it is. Diplomatic relations remain open.","The footwear representative withdraws."} }, {
    "Rest your feet. They'll still have plenty to complain about tomorrow.",
    "Dry socks and a sit down. A modest peace treaty.",
    "Nobody is making a speech about the other boot." })

card("quiet", "comfort", {
    "I'm tired of feeling like I have to earn every quiet minute.",
    "My thoughts keep going when the rest of me wants to stop.",
    "I could use company without having to be good company.",
    "I don't have much conversation in me. I don't want to sit alone, either." }, {
    agree={"Quiet company counts. We don't need to fill the space.","You can sit here without performing for anybody."},
    pushback={"You don't have to earn rest. You're allowed to need it.","Being tired isn't a debt you owe the rest of us."},
    comfort={"I'll stay a while. You don't have to find the right words.","Then we'll sit. Nothing else required."},
    deflect={"We can leave the hard conversation for another time.","No questions tonight, if that helps."} }, {
    agree={"That sounds like something I can manage.","Thanks. Quiet company is what I meant."},
    pushback={"I know. Sometimes it takes another person saying it.","I'll try to remember that while I'm sitting here."},
    comfort={"Thank you for staying.","That's enough. More than enough, just now."},
    deflect={"It would help. I'm grateful.","Another time sounds fine."} }, {
    "We can leave it quiet for a bit.","Take the minute. Nobody is counting it against you.",
    "One breath, then the next. The conversation can wait." })

card("shaken", "comfort", {
    "I'm here, but I don't feel settled inside my own skin.",
    "My hands are calmer than my thoughts. That's something, I suppose.",
    "I'd like to stop bracing for the next thing, just for a minute.",
    "I keep looking for a reason to stand up again. I need to rest." }, {
    agree={"A minute is a reasonable place to start.","Small improvements still count."},
    pushback={"Rest isn't letting anybody down.","You can be frightened and still deserve a quiet seat."},
    comfort={"I'm close by. Take your time finding your breath.","Stay here with us a little. No need to explain it."},
    deflect={"Let's leave tomorrow out of this minute.","We can talk about something ordinary, or not talk."} }, {
    agree={"A minute. I can try for that.","I'll count the small improvement, then."},
    pushback={"I needed the reminder.","All right. I'll stop arguing with the chair."},
    comfort={"Thanks. Having somebody nearby helps.","I'll stay. Just give me a moment."},
    deflect={"Ordinary would be good. Very ordinary.","Yes. Tomorrow can wait outside."} }, {
    "We don't have to fix the whole feeling tonight.","Let your shoulders come down when they're ready.",
    "Stay a while. There's room." })

card("moving", "plans", {
    "If we ever move camp, I'd like to choose the next place before we fill the bags.",
    "A better roof isn't much use if nobody can find a way home to it.",
    "We should agree what would make a move worth the trouble.",
    "I'd like a plan for leaving this place, even if we never need to use it." }, {
    agree={"A destination, a route, and somewhere to stop if we can't reach it.","Know why we're moving before we start carrying things."},
    tease={"Can the next place come with fewer stairs and better chairs?","I'll put 'already tidy' on the list of impossible demands."},
    pushback={"Every place looks better before you know what's wrong with it.","Moving has risks of its own. I want a good reason."},
    comfort={"We can work it out together. Nobody should feel left behind by the decision.","Wanting a way out doesn't mean you don't care about this place."},
    deflect={"Can we leave the bags empty until morning?","I'd like to finish sitting here before we discuss another roof."} }, {
    agree={"Exactly. A reason and a route, before the heavy lifting.","A fallback too. I don't want the road to be our only address."},
    tease={"I'll add excellent chairs, negotiable stairs.","Already tidy costs extra. We'll have to bring our own broom."},
    pushback={"Fair. We compare real problems, not imagined comforts.","A good reason is what I want us to agree on."},
    comfort={"Thanks. A plan would make staying easier too.","Yes. I want a choice, not a panic."},
    deflect={"Bags empty. Discussion postponed until we're rested.","All right. This roof gets the rest of the evening."} }, {
    "Keep a plan, and tell everyone if it changes.",
    "A home is easier to leave safely when nobody is surprised.",
    "We'll decide together before anything gets packed." })

card("chores", "plans", {
    "We ought to share the little jobs before they all become somebody's whole day.",
    "I'd like a way to ask for help before being tired turns into being angry.",
    "The quiet jobs need doing too. I'd like us to notice them.",
    "Can we agree that asking for a hand isn't a declaration of defeat?" }, {
    agree={"Fair. A small job shared is less likely to become a grudge.","We can ask what needs doing instead of waiting to be told."},
    tease={"I volunteer for inspecting whether the chairs still work.","My talents include supervising a broom from a safe distance."},
    pushback={"Sharing doesn't mean guessing who is already worn out.","Let's ask what people can manage before we assign everything."},
    comfort={"You can ask me. I don't want you wearing yourself down in silence.","We can make room for a tired day without making anybody feel useless."},
    deflect={"Let's choose one little job. A whole list is making me tired.","Could the first job be resting long enough to think clearly?"} }, {
    agree={"Good. Ask early and notice the work.","That's all I wanted. A little less guessing."},
    tease={"Chair inspection concludes shortly. The broom will want its interview.","The broom has requested closer supervision."},
    pushback={"Agreed. Ask first, then divide what remains.","Fair. Help should begin by listening."},
    comfort={"Thanks. It's easier to ask after hearing that.","A tired day with no trial attached would be welcome."},
    deflect={"One small job, after a proper rest.","Rest gets the first place on the list."} }, {
    "Ask before resentment starts answering for you.",
    "Nobody sees every job. We can help each other notice.",
    "Small work still deserves a thank you." })

L.arguments.last_run = card("argument_run", "argument", {
    "That last run still bothers me. We need a better way to agree when to turn back.",
    "About the supply run: I don't want another decision made while everyone is shouting.",
    "We shared that run. We ought to be able to talk about what worried us.",
    "Before another run, I want us to settle how we call a retreat." }, {
    agree={"All right. Next run, we agree on a way back first.","I can talk about the run without defending every second of it."},
    tease={"I didn't enjoy the excursion enough to book another.","Next time I'll bring a complaint form with the bags."},
    pushback={"You had the same few seconds I did. Don't make it sound easy now.","Talk about the decision. Don't put the whole run on me."},
    comfort={"It shook you. I hear that. Let's work out what would help.","I'd rather hear the worry than have it sit between us."},
    deflect={"I need some space before I go through that run again.","Not while we're both this wound up. Give it a little time."} }, {
    agree={"Then we start with that, before we're out there again."},
    tease={"Save the form. I want us home, not an apology afterwards."},
    pushback={"Fair. I'm asking for a different plan, not somebody to carry all the blame."},
    comfort={"Thank you. Being heard takes some of the heat out of it."},
    deflect={"All right. Space now, a proper conversation later."} }, {
    "We'll settle the next run before we leave.","Let it cool. Nobody needs another fight tonight.",
    "A better plan is worth more than winning this argument." })

L.arguments.hidden_bite = card("argument_bite", "argument", {
    "About the bite you kept from us. I need us to be honest about wounds.",
    "We know about that concealed bite now. The hiding is what I need to talk about.",
    "I'm still angry that you hid the bite. Fear doesn't make the rest of us stop caring.",
    "That bite should not have been a secret between people sharing a roof." }, {
    agree={"I should have told you. I was scared of what came next.","You're right about the hiding. I won't pretend otherwise."},
    pushback={"I was terrified. You can be angry without making me a monster.","You know now. Please talk to me like I'm still here."},
    comfort={"I'm sorry I shut you out. I didn't know how to say it.","I was frightened of losing all of you at once."},
    deflect={"I can't go through this in front of everyone. Give me a minute.","I need this conversation to slow down."} }, {
    agree={"Thank you for saying it. I wanted the truth."},
    pushback={"You're still here. That's why the truth matters to me."},
    comfort={"I can hear the fear. I still need the honesty."},
    deflect={"We'll give it space. We won't turn it back into a secret."} }, {
    "Honest about wounds. Decent about the person. Both matter.",
    "Keep talking to each other. Don't decide everything in anger.",
    "Nobody needs to make this harder with a raised voice." })

L.arguments.fled_fight = card("argument_fled", "argument", {
    "When you ran from that fight, it left something between us. We need to talk.",
    "About leaving the fight: I need to know how we warn each other next time.",
    "I can't leave that withdrawal sitting in my head without an answer.",
    "We know you fled. I'm asking what we do differently when fear hits again." }, {
    agree={"I panicked. Next time I need to call it before I run.","I should have warned you. I know that."},
    tease={"My legs made the decision before the committee could meet.","I wasn't leaving to get a better seat."},
    pushback={"I was frightened. Calling me a coward won't make us safer.","I couldn't stay in that fight. I should have said so sooner."},
    comfort={"I don't want that to happen between us again.","I hear how it felt to be left. I'm sorry."},
    deflect={"I'm not ready to unpack that fight while we're angry.","Give me a little room before we go through it."} }, {
    agree={"A warning. That's what I need from you."},
    tease={"Keep the joke. Give me a warning next time."},
    pushback={"I'm asking for a warning, not a person without fear."},
    comfort={"Then we find a signal we can both use when we're scared."},
    deflect={"Room now. We still have to settle a warning later."} }, {
    "Nobody gets braver by being shouted at.","Agree on a warning before another fight.",
    "Let the anger go down before it chooses the words." })

L.arguments.food_eaten = card("argument_food", "argument", {
    "About the food you ate. We need to agree what belongs to the shared reserve.",
    "That missing food wasn't just a private meal. It was part of the reserve.",
    "I want to talk about the food before resentment starts counting portions.",
    "You ate from the shared food. I need us to settle a rule everyone understands." }, {
    agree={"I should have asked. Let's make the reserve clear.","I ate it. I'm not going to make you prove that twice."},
    tease={"The supper committee has discovered its first scandal.","I didn't expect dinner to have a hearing afterwards."},
    pushback={"I was hungry. We need a fair rule, not a trial over a meal.","I'll talk about sharing. Don't talk as though needing food is a crime."},
    comfort={"I didn't think enough about what it meant to everyone else.","I'm sorry. Let's agree on what happens when somebody needs more."},
    deflect={"Can we settle this when hunger isn't doing the talking?","I need a minute before this becomes a worse argument."} }, {
    agree={"Good. Clear reserve, clear agreement."},
    tease={"Then let's end the hearing with a rule we can live by."},
    pushback={"A fair rule is exactly what I want. Hunger still gets heard."},
    comfort={"Thank you. Asking for more should be possible without hiding it."},
    deflect={"A minute, then. The reserve still needs an agreement."} }, {
    "Share the rule as clearly as the food.","Nobody should have to guess what is set aside.",
    "A fair meal matters more than a winning argument." })

L.arguments.door_open = card("argument_door", "argument", {
    "About the door you left open. We need a habit that doesn't depend on guessing.",
    "That open door has been bothering me. Please check it when you come through.",
    "You left the door open. I want a simple agreement before it happens again.",
    "We need to talk about shutting the door behind us. It's a small thing with large consequences." }, {
    agree={"I left it open. I'll check it when I come through.","You're right. One last look before I walk away."},
    tease={"The door has acquired a very stern supervisor.","I didn't realise the hinges had appointed counsel."},
    pushback={"I made a mistake. Speak to me, not at me.","I'll check it. You don't need to turn one mistake into my whole character."},
    comfort={"I'm sorry it left you worrying. I'll make a habit of checking.","I understand why it upset you."},
    deflect={"I heard you. Give me a minute before we keep at each other.","Let's stop while this is still about a door."} }, {
    agree={"That's all I was asking. Thank you."},
    tease={"Then tell the hinges the supervisor would like it shut."},
    pushback={"Fair. The habit matters more than making you feel small."},
    comfort={"Thank you. A check at the door would help."},
    deflect={"Agreed. A door, not a verdict on either of us."} }, {
    "Check it behind you. We can leave the rest here.","A small habit is enough. No more speeches.",
    "Keep the door shut and the conversation civil." })

L.makeup = card("makeup", "makeup", {
    "About our argument over {reason}. I'd rather settle it than keep feeding it.",
    "I've had time to cool down about {reason}. Can we start again?",
    "I don't want {reason} to be the only thing we say to each other.",
    "Can we talk quietly about {reason}? I don't need to win it now." }, {
    agree={"Yes. Let's keep the useful part and lose the shouting.","I'd like that. We still have to live beside each other."},
    pushback={"We can start again. I still need you to hear my side.","I'll let the anger go. The agreement still matters."},
    comfort={"I'm glad you asked. I don't like the space it put between us.","Come on. We can do better than staying angry."},
    deflect={"Slowly, then. I'm willing to try.","We can begin with a quieter minute."} }, {
    agree={"Good. Next time, the useful part first."},
    pushback={"I'll listen. That's what I should have done sooner."},
    comfort={"Neither do I. I'd like the space gone."},
    deflect={"Slowly is fine. I'm here."} }, {
    "All right. We can leave the shouting behind.","Keep talking before it grows teeth again.",
    "A quieter start is still a start." }, {"has_reason"}, {"named_argument"})

L.aftermath.death = card("after_death", "aftermath", {
    "{name} is gone. I keep expecting to hear that voice again.",
    "I don't know how to speak about losing {name} without stopping halfway.",
    "We lost {name}. I'd like us to take a moment together.",
    "I need to say the name out loud. {name}. We shouldn't have to carry this alone." }, {
    agree={"We can take that moment. Nothing needs to fill it.","Say the name. I'm listening."},
    pushback={"Don't ask yourself to carry everyone's grief as well as your own.","You don't have to find words that make it bearable for us."},
    comfort={"I'm here. We can remember {name} together.","There's room for the grief here. Stay with us a while."},
    deflect={"I can't find much to say either. I can stay.","We don't have to talk beyond the name just now."} }, {
    agree={"Thank you. A moment together is what I needed."},
    pushback={"I know. It's hard to put any of it down."},
    comfort={"I'd like that. I don't want to sit with this alone."},
    deflect={"Staying is enough. Thank you."} }, {
    "We can sit a little longer.","Nobody has to hurry this part.",
    "We'll remember the person, together." }, {"known","death","has_name"}, {"observed_or_told_loss"})

L.aftermath.close_call = card("after_close", "aftermath", {
    "That close call at {place}. I need a moment to let it sink in.",
    "We're here after that close call at {place}. I'm still catching up with that.",
    "I keep going back to that narrow escape at {place}.",
    "After that close call at {place}, a quiet minute feels like more than a quiet minute." }, {
    agree={"A minute sounds right. Let the breathing settle.","We're here for this conversation. Hold on to that."},
    tease={"We could find a less demanding way to appreciate sitting down.","I'd like the next lesson in gratitude to involve a chair."},
    pushback={"We should talk about what to change before we try it again.","Take the minute. Then let's agree on a safer way."},
    comfort={"Stay near me while it settles.","No need to look steady for our benefit."},
    deflect={"I'd rather not go through every second of it yet.","We can leave the details until our hands are quieter."} }, {
    agree={"Yes. One breath at a time for now."},
    tease={"A chair with no lesson attached would suit me."},
    pushback={"Agreed. Rest first, then a better plan."},
    comfort={"Thank you. I could use the company."},
    deflect={"Fine by me. The details can wait."} }, {
    "Nobody needs to rush back out to prove anything.","Let it settle. We're listening.",
    "A little quiet before the next decision." }, {"known","close_call","has_place"}, {"observed_or_told_escape"})

L.aftermath.homecoming = card("after_home", "aftermath", {
    "We're back from the expedition. It's good to say that where you can hear it.",
    "Back here after the expedition. I need to put the road down for a while.",
    "We've come home from the expedition. Give us a minute to feel home.",
    "The expedition is over. I'd like a quiet word before we all scatter." }, {
    agree={"Good to hear it from you. Take a seat before the report.","Welcome back. The details can follow a breath."},
    tease={"The road hasn't followed you indoors, has it?","I'll put 'sitting down' at the top of the welcome."},
    pushback={"Rest first, but tell us what we need to know before anyone goes out again.","Don't carry the whole report alone. Let the crew speak too."},
    comfort={"I'm glad you're here to tell us about it.","You can put the road down. We'll listen."},
    deflect={"A quiet minute first. No questions until you're ready.","We can leave the inventory for another moment."} }, {
    agree={"A seat first would be good. Then we can talk."},
    tease={"If it knocks, tell it we're closed."},
    pushback={"Fair. We'll share what we know after a breath."},
    comfort={"Thank you. Hearing that helps it feel like home."},
    deflect={"Thanks. Just a minute, then the details."} }, {
    "Let everyone have a moment before the next job.","Home first. Report second.",
    "Stay together a little. There's time to unpack." }, {"known","homecoming","crew_returned"}, {"actual_expedition_return"})

L.aftermath.alarm = card("after_alarm", "aftermath", {
    "The alarm is quiet now. My ears haven't quite accepted it.",
    "After that alarm, even this silence sounds loud.",
    "We dealt with that alarm. I'd like a moment before somebody makes another noise.",
    "The alarm's over. Give me a second to stop listening for it." }, {
    agree={"A quiet second. That's a fair request.","Let the silence do its work for a moment."},
    tease={"I'll put the silence in charge of entertainment.","No encore requested. I'll write that down."},
    pushback={"Once we're settled, we should agree what to do if it happens again.","Let's keep the quiet without assuming it solves everything."},
    comfort={"Take the moment. I'm close by.","I know. A noise like that can stay with you."},
    deflect={"I have no plans to add to the noise.","The discussion can be quiet too."} }, {
    agree={"Good. Just let it be quiet."},
    tease={"For once, entertainment has an excellent programme."},
    pushback={"Agreed. One quiet minute, then we talk it through."},
    comfort={"Thanks. Company helps with the ringing."},
    deflect={"Quiet discussion approved."} }, {
    "Let the quiet stay a little.","Nobody volunteer a demonstration.",
    "A calm minute before the next decision." }, {"known","alarm","all_clear"}, {"actual_fought_off_alarm"})

return L
