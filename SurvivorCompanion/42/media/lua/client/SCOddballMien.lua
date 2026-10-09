-- SPDX-License-Identifier: MIT
-- Mien's seven-day batch is a saved world-time contract with exact supplies.
local SC=SurvivorCompanion
SC.OddballMien=SC.OddballMien or {}
local Mien=SC.OddballMien
local ID="mien_ward"
local REQUIREMENTS={ ["Base.Hops"]=4,["Base.Yeast"]=2,
    ["Base.Sugar"]=2,["Base.Bucket"]=1 }
local LINES={
    "Name's Mien Ward. You like hops? Everybody likes hops. Some just don't know it yet.",
    "Cascade, Chinook, Centennial. The three C's. Say them with me.",
    "Dethroned God called this. Track four, Hymns for the Unburied. Prophets, man.",
    "This saucepan's brewed eleven batches and cracked nine skulls. Lucky saucepan.",
    "The dead are a problem. You know what else is? Skunky beer.",
    "Moonshine is paint thinner with ambition. The Bledsoes can keep it.",
    "Elvis against metal? Tupelo Boys, we can settle that after a proper stout.",
}
local function U() return SC.GameplayUtil end
local function story(g)
    local v=g and g.oddball
    if type(v)~="table" or v.id~=ID then return nil end
    v.stage=v.stage or "hunting_ingredients"
    return v
end
local function actorFor(g)
    local m=g and g.members and g.members[1]
    local r=m and m.actorId and SC.Registry and SC.Registry.byId(m.actorId)
    return r and r.actor and U().isValidActor(r.actor) and r.actor or nil
end
local function near(g,p)
    local a=actorFor(g)
    return a and p and U().distance(a,p)<=7 and U().canSee(p,a)==true
end
local function ageHours()
    local t=type(getGameTime)=="function" and getGameTime()
    local h=t and select(1,U().call(t,"getWorldAgeHours"))
    return tonumber(h)
end
local function itemFor(a,kind)
    local inv=a and U().inventory(a)
    for _,item in ipairs(inv and U().inventoryItemsDeep(inv,240,8) or {}) do
        if U().itemType(item)==kind then return item end
    end
end
local function stock(a,g)
    local found={}
    local inv=a and U().inventory(a)
    for _,item in ipairs(inv and U().inventoryItemsDeep(inv,240,8) or {}) do
        local data=U().modData(item)
        if U().itemType(item)=="Base.BeerBottle" and data
            and data.lfMienBatch==g.id then found[#found+1]=item end
    end
    return found
end
local function holdSaucepan(a)
    local pan=itemFor(a,"Base.Saucepan")
    if pan then U().call(a,"setPrimaryHandItem",pan) end
    return pan
end
local function nearbyRival(actor, id)
    for _,other in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        if other.oddball and other.oddball.id==id then
            local member=other.members and other.members[1]
            local record=member and member.actorId
                and SC.Registry.byId(member.actorId)
            if record and record.actor and U().isValidActor(record.actor)
                and U().distance(actor,record.actor)<=7 then
                return record.actor end
        end
    end
end
function Mien.onSpawn(g,a)
    local v=story(g)
    if not v or not a then return false,"brewer_unavailable" end
    local inv=U().inventory(a)
    if not inv then return false,"inventory_unavailable" end
    if not v.gearSeeded then
        local pan=itemFor(a,"Base.Saucepan") or U().addItem(inv,"Base.Saucepan")
        local opener=U().addItem(inv,"Base.BottleOpener")
        if pan and opener then v.gearSeeded=true end
    end
    holdSaucepan(a)
    return v.gearSeeded==true,"lucky_saucepan_ready"
end
function Mien.pulse(g,p,current)
    local v=story(g)
    if not v then return false,"wrong_oddball" end
    local a=actorFor(g)
    if not a then return false,"brewer_unloaded" end
    current=tonumber(current) or U().nowMs()
    if near(g,p) and not v.greeted then
        v.greeted=true
        g.discovered=true
        U().say(a,LINES[1])
    end
    if near(g,p) and current>=(tonumber(v.nextRivalCheckAt) or 0) then
        v.nextRivalCheckAt=current+30000
        if not v.bledsoeRemark and nearbyRival(a,"bledsoe_brothers_still") then
            v.bledsoeRemark=true
            U().say(a,"Moonshine is paint thinner with ambition. Ask me about hops.")
        elseif not v.tupeloRemark and nearbyRival(a,"tupelo_boys") then
            v.tupeloRemark=true
            U().say(a,"Elvis versus metal. After this stout, we settle it.")
        end
    end
    local hour=ageHours()
    if v.stage=="fermenting" and hour
        and hour>=(tonumber(v.brewStartHour) or math.huge)+168 then
        local inv=U().inventory(a)
        v.beerSeeded=tonumber(v.beerSeeded) or 0
        while v.beerSeeded<6 do
            local beer=U().addItem(inv,"Base.BeerBottle")
            if not beer then break end
            local data=U().modData(beer)
            if data then data.lfMienBatch=g.id end
            v.beerSeeded=v.beerSeeded+1
        end
        if v.beerSeeded==6 then
            v.stage="batch_ready"
            U().say(a,
                "Behold: Unburied Imperial Stout. Eleven percent. Don't drive. Can't anyway.")
        end
    end
    return true,v.stage
end
function Mien.pulseRecruited(g,a,p,current)
    if story(g) and a and not itemFor(a,"Base.Saucepan") then
        return false,"lucky_saucepan_missing" end
    if a then holdSaucepan(a) end
    return true,"still_talking_hops"
end
function Mien.intentFor(a,p,s,g)
    local v=story(g)
    if not v then return nil end
    if g.standing=="Hostile" then return {mode="hostile",priority=110} end
    local threats=s and (tonumber(s.threatCount) or #(s.threats or {})) or 0
    if threats>0 then
        local now=U().nowMs()
        if now>=(tonumber(v.nextFightLineAt) or 0) then
            v.nextFightLineAt=now+60000
            U().say(a,U().config("profanityEnabled")==false
                and "Horns up, you rotten freaks! Dethroned God forever!"
                or "Horns up, you rotten bastards! Dethroned God forever!")
        end
        return {mode="zombie_defense",priority=18}
    end
    return {mode="oddball_idle",priority=28}
end
function Mien.canRecruit(g)
    local v=story(g)
    return v and v.stage=="batch_claimed" and g.standing=="Trusted" or false,
        "finish_the_unburied_batch"
end
function Mien.menuOptions(g,p)
    local v=story(g)
    if not v or not near(g,p) then return {} end
    return {
        {id="ask_hops",label="Ask Mien about the dead",enabled=true},
        {id="hops_seed",label="Ask for hops seed",
            enabled=not v.seedGiven and g.standing~="Hostile"},
        {id="start_brew",label="Bring hops, yeast, sugar and a bucket",
            enabled=v.stage=="hunting_ingredients" and
                SC.OddballExchange.select(p,REQUIREMENTS)~=nil},
        {id="claim_batch",label="Collect six bottles of Unburied Imperial Stout",
            enabled=v.stage=="batch_ready" and #stock(actorFor(g),g)==6},
        {id="recruit",label="Ask Mien to join",
            enabled=Mien.canRecruit(g)==true},
    }
end
function Mien.action(g,action,p)
    local v=story(g)
    if not v then return false,"wrong_oddball" end
    if action=="hurt" then return SC.Factions.forceStanding(g.id,"Hostile") end
    if not near(g,p) then return false,"brewer_too_far" end
    local a=actorFor(g)
    if action=="ask_hops" then
        v.line=((tonumber(v.line) or 0)%(#LINES-1))+2
        U().say(a,LINES[v.line])
        return true,"hops_again"
    end
    if action=="hops_seed" and not v.seedGiven then
        local seed=U().addItem(U().inventory(p),"Base.HopsSeed")
        if not seed then return false,"hops_seed_unavailable" end
        v.seedGiven=true
        SC.Factions.adjustStanding(g.id,8,"hops_seed_gift")
        U().say(a,"Plant these. Your grandkids will thank you. Mostly for the hops.")
        return true,"real_hops_seed_given"
    end
    if action=="start_brew" and v.stage=="hunting_ingredients" then
        local hour=ageHours()
        if not hour then return false,"world_clock_unavailable" end
        local moved,reason=SC.OddballExchange.take(p,a,REQUIREMENTS)
        if not moved then return false,reason end
        v.stage="fermenting"
        v.brewStartHour=hour
        U().say(a,"Four hops, two yeast, two sugar, one bucket. Give it seven days.")
        return true,"exact_brew_supplies_received"
    end
    if action=="claim_batch" and v.stage=="batch_ready" then
        local bottles=stock(a,g)
        if #bottles~=6 then return false,"batch_stock_unavailable" end
        local moved={}
        local target=U().inventory(p)
        for _,item in ipairs(bottles) do
            local source=select(1,U().call(item,"getContainer"))
            if not source or not U().transferItemVerified(source,target,item) then
                for _,entry in ipairs(moved) do
                    U().transferItemVerified(target,entry.source,entry.item)
                end
                return false,"batch_transfer_failed"
            end
            moved[#moved+1]={source=source,item=item}
        end
        v.stage="batch_claimed"
        SC.Factions.forceStanding(g.id,"Trusted")
        U().say(a,"Unburied Imperial Stout. Take all six. Now, about the hops...")
        return true,"six_real_beers_delivered"
    end
    if action=="recruit" and Mien.canRecruit(g)==true
        and SC.FactionRecruitment then
        local asked,reason=SC.FactionRecruitment.ask(g.id,p,false)
        if not asked then return false,reason end
        U().say(a,"I'm in. But we stop at every store. For yeast. Always for yeast.")
        return SC.FactionRecruitment.startTrial(g.id,p,false)
    end
    return false,"brewer_choice_unavailable"
end
return Mien
