-- SPDX-License-Identifier: MIT
-- Authored pre-outbreak fiction tied to the companion's existing background.
-- The three reveal flags are committed only after actual spoken delivery.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local B={stories={profession={},fear={},value={}},catalogs={}} SC.DeepBackground=B
B.stories.profession={
    burglar="I once waited half a night for a house to go quiet, then heard a child crying inside. I went home empty-handed. I never put that one in my better stories.",
    burgerflipper="A man used to come in just before closing and order one plain burger. I started keeping the grill warm a few extra minutes. He always looked relieved to be expected.",
    carpenter="I put a door in crooked early in my working life. My foreman made me sit and watch it swing open by itself. I've never forgotten a lesson that quiet.",
    chef="A dishwasher at my old kitchen could tell who was having a bad day by what they left on a plate. I thought I was the observant one until I worked beside her.",
    constructionworker="A new fellow on a site once asked me the same question three times. I nearly snapped. Then I remembered how many things on a site can kill a man who's ashamed to ask twice.",
    doctor="I used to keep a chair beside the examination table for people who wanted someone with them. The chair did more good than some of the things I could prescribe.",
    electrician="I spent an entire morning tracing a fault that turned out to be one loose connection. The customer apologised for wasting my time. Finding the small thing was the work.",
    engineer="A drawing of mine once looked excellent until a man who had to build it asked where he'd put his hands. I started leaving room for people, after that.",
    farmer="There was a patch of ground I kept blaming for a poor crop. An older neighbour asked what I'd done for the soil lately. I didn't enjoy the question. It was the right one.",
    fireofficer="After one call, a family thanked us for saving a box of photographs. I had barely noticed the box while carrying it. You don't always know what you're bringing back to somebody.",
    fisherman="I knew a fellow who could sit beside the water all morning without calling it wasted time. I used to think he was making excuses. These days I think he knew something.",
    fitnessinstructor="One woman at the gym was proud of walking a little farther each week. Nobody else noticed the distance. I learned to ask what a good day meant before telling people how to have one.",
    lumberjack="An old hand on a logging crew told me to watch the tired man as closely as the tree. He said a tree usually gives you more warning. I still think about that.",
    mechanics="A woman brought a car back because the noise was gone and she couldn't believe it. I drove round the block with her until she stopped listening for it. Sometimes the repair needs a witness.",
    metalworker="I once polished a piece until it looked better than it fitted. The fellow waiting for it wasn't impressed by the shine. A good fit has been my favourite finish ever since.",
    nurse="There was a patient who apologised every time he asked for water. I put the cup where he could reach it, then sat long enough to tell him he wasn't causing trouble by being thirsty.",
    parkranger="A lost walker once insisted he hadn't been lost, just delayed. I walked him out without arguing over the word. Getting somebody home matters more than winning the definition.",
    policeofficer="I once spent an hour settling an argument that had started with a fence and ended up about twenty years of being ignored. The fence was the easy part to mend.",
    rancher="An animal I'd raised would come to the gate when it heard my boots. I used to call that habit. I think I was avoiding the word trust because it made the work harder.",
    repairman="I fixed a woman's cupboard and she asked me to stay for tea. She'd been waiting all week for someone to knock. I took my time packing the tools.",
    securityguard="On a night shift, the cleaner and I used to leave each other notes about which light was flickering. Nothing important. I miss knowing whose handwriting would be there in the morning.",
    smither="A customer once asked why I was taking so long over a tool nobody would admire. I told him someone would have to trust it with their hands. That seemed a good enough reason.",
    tailor="I repaired a coat for a man who kept asking whether the mend would show. He relaxed when I said it would hold. I think he'd been asking two different questions.",
    unemployed="When work was scarce, I used to invent errands so I wouldn't spend the whole day feeling useless. A neighbour asked me to carry a box once. I was grateful for a reason to be needed.",
    veteran="I remember somebody teaching a frightened newcomer how to fold a blanket. No speech about courage. Just a patient pair of hands and one small thing he could get right.",
}
B.stories.fear={
    being_alone="I used to leave a radio on in an empty room. I'd say I liked the programme, even when it was only advertisements. A human voice made the walls feel farther apart.",
    turning="What frightens me is the thought of people having to decide what I am while I'm still trying to tell them. I need the person to matter, even when the answer is hard.",
    fire="A small flame can still hold my attention longer than I want it to. I watch the edges, the things beside it, the way out. Knowing why I'm afraid doesn't make it switch off.",
    tight_spaces="I used to choose the seat nearest an aisle and pretend it was chance. I like knowing I can get up without asking everybody else to move. It's a small kindness I can give myself.",
    letting_people_down="I can turn one person's disappointment into a whole room judging me, even when the room is empty. I'm learning to ask what people actually need instead of guessing the worst.",
    the_dark="I used to check a room before turning out the light, then feel foolish about it. Now I try to be kinder to the part of me that wants to know where the door is.",
}
B.stories.value={
    honesty="I told an easy lie once and spent longer arranging the next conversation than the truth would have taken. I remember how tired it made me. I'd rather carry the awkward truth now.",
    loyalty="Somebody once stayed with me through a long, thoroughly uninteresting wait. No crisis, no reward. I think of that when I try to say what loyalty means without making it sound grand.",
    kindness="A stranger once gave me directions without making me feel foolish for asking. It was such a little thing. I can still remember the relief of not having to defend being lost.",
    self_reliance="I used to think relying on myself meant never asking. Then I learned how much work it took other people to guess what I needed. Asking plainly can be a kind of independence too.",
    community="I remember a street where people returned each other's empty dishes. You could tell who was being looked after by the bowls going from door to door. That's the sort of order I still want.",
    courage="The bravest thing I remember from before this was somebody admitting they couldn't manage alone. No audience applauded. A few people simply moved closer and helped.",
}
local rank={cautious=0,ally=1,trusted=2,close=3,family=4}
local rules={{kind="profession",day=7,tier="trusted"},{kind="fear",day=30,tier="close"},{kind="value",day=100,tier="family"}}
local function pool(id,text)
    local topic="background.depth_"..id
    local packets={{id=topic,scene=topic,ideaId=topic,shape="background",voiceWeights={common=1},
        requires={"background_known"},asserts={"authored_background"},variants={{id="1",text=text,clean=text}}}}
    B.catalogs[#B.catalogs+1]=packets
    SC.Dialogue.register(topic,{common={{text,clean=text}}})
    return {topic=topic,packets=packets}
end
local pools={}
for kind,stories in pairs(B.stories) do for code,line in pairs(stories) do pools[kind..":"..code]=pool(kind.."_"..code,line) end end
local follow=pool("reflection","I hadn't said that part aloud for a while. Thank you for listening without trying to tidy it up.")
local close=pool("close","We can leave a little room for who we were before all this.")
local answers={
    agree=pool("reply_agree","I'm listening. A little part of your life is still worth the time."),
    tease=pool("reply_tease","You've been keeping the interesting conversation in reserve, then."),
    pushback=pool("reply_pushback","You don't have to turn the story into a lesson for the rest of us."),
    comfort=pool("reply_comfort","Thank you for telling us. I like knowing the person behind the work."),
    deflect=pool("reply_deflect","I haven't much to add. I'd rather listen for a while."),
}
function B.prepare(actor,state)
    if (tonumber((state.reveals or {}).background) or 0)<7 then return nil end
    local days=SC.VoiceMemory.daysTogether(actor)
    local tier=SC.Relationship.tier(state)
    local background=state.background or {}
    local _,profession=SC.Background.definition(background)
    local codes={profession=profession,fear=background.fear,value=background.value}
    for _,rule in ipairs(rules) do
        local key="depth_"..rule.kind
        local chosen=pools[rule.kind..":"..tostring(codes[rule.kind])]
        if chosen and not (state.reveals or {})[key] and days>=rule.day and rank[tier]>=rank[rule.tier] then
            return chosen,{backgroundReveal=key,topic=chosen.topic}
        end
    end
end
function B.line(actor,state)
    local chosen,receipt=B.prepare(actor,state)
    if not chosen then return nil end
    local lines=SC.DiaryText.spokenCandidates({evidence={background_known=true},tokens={}},chosen.packets)
    local line=SC.Dialogue.choose(actor,chosen.topic,{common=lines},nil,{state=state})
    return line,receipt
end
function B.commit(actor,receipt)
    if not receipt or not receipt.backgroundReveal then return end
    local state=SC.Commands.peek(actor)
    state.reveals=state.reveals or {} state.reveals[receipt.backgroundReveal]=true
    if SC.Commands.persist then SC.Commands.persist(actor) end
end
function B.scene(actor,state)
    local chosen,receipt=B.prepare(actor,state)
    if not chosen then return nil end
    local card={id=chosen.topic,kind="background",open=chosen,close=close}
    for _,tag in ipairs({"agree","tease","pushback","comfort","deflect"}) do
        card["reply_"..tag]=answers[tag] card["follow_"..tag]=follow
    end
    return card,{context={evidence={background_known=true},tokens={}},backgroundReceipt=receipt}
end
return B
