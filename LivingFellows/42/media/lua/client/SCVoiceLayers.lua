-- SPDX-License-Identifier: MIT
LivingFellows=LivingFellows or {}
local SC=LivingFellows
local L={lines={}} SC.VoiceLayers=L
local function add(topic,day,tier,lines)
    L.lines[topic]=L.lines[topic] or {}
    for _,line in ipairs(lines) do L.lines[topic][#L.lines[topic]+1]={line,clean=line,after_day=day,tier=tier} end
end
add("banter.routine",7,"trusted",{
    "It's easier to let a quiet minute stay quiet with familiar people nearby.",
    "I don't have to introduce myself to every silence here now.",
    "Ordinary company. I hadn't realised how much I needed it.",
    "I can leave a thought unfinished around you. That's a kind of comfort."})
add("banter.routine",30,"close",{
    "A place begins to feel like home when you know whose footsteps you're hoping to hear.",
    "I used to spend all my energy looking ready. It's easier to admit I'm tired now.",
    "We don't need a grand occasion to sit together. I like that.",
    "Some of the life I want to keep is right here, being ordinary for a minute."})
add("banter.routine",100,"family",{
    "Whatever tomorrow asks of us, I want to keep this small habit of being together.",
    "I don't think of company as an extra any more. It's part of what keeps me going.",
    "There are things I can say here that used to stay in my head for years.",
    "Familiar voices. A plain evening. I know what I'd be trying to protect."})
add("banter.follow",7,"trusted",{
    "A little easier to keep moving when I know the people beside me.",
    "I'll speak up if I need a rest. I'd rather ask than quietly fall behind.",
    "We can leave room for a slower pace when somebody needs it.",
    "No prize for arriving too tired to think."})
add("banter.follow",30,"close",{
    "I like having somebody I can ask to slow down without making a speech.",
    "I'd rather take an ordinary walk together than make every road a test.",
    "A familiar voice makes the road feel a little less empty.",
    "We don't have to fill every stretch with talk. Company still counts."})
add("banter.follow",100,"family",{
    "Home is beginning to mean the people I want beside me on the way back.",
    "I can ask for a hand here without wondering what it will cost me later.",
    "I still watch the road. I just don't feel I have to carry it alone.",
    "I'd like there to be plenty of dull walks left for us."})
local cache=setmetatable({},{__mode="k"})
function L.extend(topic,source)
    local additions=L.lines[topic]
    if not additions or type(source)~="table" then return source end
    local prior=cache[source]
    if prior and prior.topic==topic then return prior.value end
    local copy={} for key,value in pairs(source) do if type(key)~="number" then copy[key]=value end end
    local common={}
    for _,line in ipairs(source.common or source.all or source) do common[#common+1]=line end
    for _,line in ipairs(additions) do common[#common+1]=line end
    copy.common=common
    cache[source]={topic=topic,value=copy}
    return copy
end
local ranks={cautious=0,ally=1,trusted=2,close=3,family=4}
function L.allowed(line,state)
    if type(line)~="table" then return true end
    local day=SC.LifeEvents and math.floor(SC.LifeEvents.now()/86400000) or 0
    if line.after_day and day<line.after_day then return false end
    if line.tier then
        local tier=SC.Relationship and SC.Relationship.tier(state) or "cautious"
        if (ranks[tier] or 0)<(ranks[line.tier] or 99) then return false end
    end
    return true
end
return L
