-- SPDX-License-Identifier: MIT
require "SCEmmaSurvivalData"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.EmmaSurvival = SC.EmmaSurvival or {}
local S = SC.EmmaSurvival
local titles={water_purify="Safe drinking water",water_find="Finding water",food_spoil="Food spoilage",
    food_preserve="Preserving food",cooking="Cooking without mains power",bleeding="Bleeding and dressings",
    deep_wound="Deep wounds and stitches",glass_bullet="Glass and lodged bullets",fracture="Broken bones",
    wound_infection="Ordinary wound infection",herbs="Medicinal plants",pills="Medicine reference",
    bite="Bites and Knox infection",sickness="Sickness and corpse exposure",generator="Generator basics",
    car_start="Starting a vehicle",fuel="Finding gasoline",noise="Noise and infected",barricade="Securing a building",
    sleep="Finding somewhere to sleep",farming="Growing food",warmth="Warmth and exposure",
    combat="Surviving a fight",weapons="Choosing a weapon",skills="Learning skills",light="Light after dark"}
function S.install()
    local c=SC.TerminalConversation
    if not c or S.installed==c then return end
    S.installed=c
    for _,topic in ipairs(SC.EmmaSurvivalData) do
        c.GUIDES[#c.GUIDES+1]={id="survival_"..topic.id,title=titles[topic.id] or topic.id:gsub("_"," "),
            questions=topic.questions,pages=topic.pages,survival=true,quips=topic.quips}
    end
    c.questionIndex,c.questionForms=nil,nil
end
return S
