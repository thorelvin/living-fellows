-- SPDX-License-Identifier: MIT
-- One native actor, two voices, one real doll and a permanent fork.
local SC = SurvivorCompanion
SC.OddballMorton = SC.OddballMorton or {}
local Morton = SC.OddballMorton
local ID = "morton_buster"
local function U() return SC.GameplayUtil end
local function story(g)
    local v = g and g.oddball
    if type(v) ~= "table" or v.id ~= ID then return nil end
    v.stage = v.stage or "performing"
    return v
end
local function actorFor(g)
    local m = g and g.members and g.members[1]
    local r = m and m.actorId and SC.Registry and SC.Registry.byId(m.actorId)
    return r and r.actor and U().isValidActor(r.actor) and r.actor or nil
end
local function near(g,p)
    local a=actorFor(g)
    return a and p and U().distance(a,p)<=8 and U().canSee(p,a)==true
end
local function doll(a)
    local inv=a and U().inventory(a)
    for _,item in ipairs(inv and U().inventoryItemsDeep(inv,120,8) or {}) do
        if U().itemType(item)=="Base.Doll" then return item end
    end
end
local function chair(v)
    local p=v.site and v.site.chair
    local sq=p and U().gridSquare(p.x,p.y,p.z or 0)
    local objects=sq and select(1,U().call(sq,"getObjects"))
    return objects and SC.NativeList and SC.NativeList.get(objects,p.objectIndex)
end
local function sayBuster(actor, raw, edited)
    U().say(actor, "Buster: " .. (U().config("profanityEnabled")==false
        and (edited or raw) or raw))
end
local function bloodOnPlayer(player)
    local visual=player and select(1,U().call(player,"getHumanVisual"))
    if not visual or BloodBodyPartType==nil then return false end
    for index=0,16 do
        local part=BloodBodyPartType.FromIndex(index)
        if part then
            local blood=select(1,U().call(visual,"getBlood",part))
            if (tonumber(blood) or 0)>0.18 then return true end
        end
    end
    return false
end
local function raccoonNear(actor)
    for _,other in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        if other.oddball and other.oddball.id=="big_chris_rascal"
            and SC.OddballAnimals then
            local animal=SC.OddballAnimals.find(other,1)
            if animal and U().distance(actor,animal)<=7 then return true end
        end
    end
    return false
end
local function costumeNear(actor)
    local costumeItems = {
        ["Base.BunnySuitBlack"] = true,
        ["Base.BunnySuitPink"] = true,
        ["Base.Hat_BunnyEarsBlack"] = true,
        ["Base.Hat_BunnyEarsWhite"] = true,
        ["Base.Hat_Fireman"] = true,
        ["Base.Trousers_Fireman"] = true,
        ["Base.Hat_CrashHelmet_Police"] = true,
        ["Base.Jacket_Police"] = true,
        ["Base.Trousers_Police"] = true,
    }
    for _,other in ipairs(SC.Factions and SC.Factions.list(false) or {}) do
        if other.oddball and other.oddball.id=="sleeping_it_off" then
            local m=other.members and other.members[1]
            local r=m and m.actorId and SC.Registry.byId(m.actorId)
            if r and r.actor and U().distance(actor,r.actor)<=7 then
                local worn=select(1,U().call(r.actor,"getWornItems"))
                local count=worn and SC.NativeList and SC.NativeList.size(worn)
                    or 0
                for index=0,math.min(63,count-1) do
                    local entry=SC.NativeList.get(worn,index)
                    local item=entry and select(1,U().call(entry,"getItem"))
                    if costumeItems[U().itemType(item)] then return true end
                end
            end
        end
    end
    return false
end
function Morton.onSpawn(g,a)
    local v=story(g)
    if not v or not a then return false,"performer_unavailable" end
    if v.dollSeeded then return true,"buster_present" end
    local puppet=doll(a) or U().addItem(U().inventory(a),"Base.Doll")
    if not puppet then return false,"buster_doll_unavailable" end
    U().call(puppet,"setName","Buster")
    U().call(a,"setPrimaryHandItem",puppet)
    v.dollSeeded=true
    return true,"buster_in_hand"
end
function Morton.pulse(g,p,current)
    local v=story(g)
    if not v then return false,"wrong_oddball" end
    local a=actorFor(g)
    if not a then return false,"performer_unloaded" end
    if near(g,p) then
        g.discovered=true
        if not v.greeted then
            v.greeted=true
            sayBuster(a,"Well, look what the dead dragged in. Two of 'em.")
            U().say(a,"Morton: Buster! Manners! I'm so sorry. He's been cooped up.")
            v.nextLineAt=current+9000
        elseif v.stage=="performing"
            and current>=(tonumber(v.nextLineAt) or math.huge) then
            local cycle=((tonumber(v.line) or 0)%4)+1
            v.line=cycle
            if cycle==1 then
                sayBuster(a,"Cooped up with YOU, dipshit. Thirty days. Somebody kill me.",
                    "Cooped up with YOU, genius. Thirty days. Somebody save me.")
            elseif cycle==2 then
                U().say(a,"Morton: We did birthday parties. And weddings. And one very sad funeral.")
            elseif cycle==3 then
                sayBuster(a,"Hell of a funeral. Best crowd we ever had. Nobody heckled.",
                    "Heck of a funeral. Best crowd we ever had. Nobody heckled.")
            else
                sayBuster(a,"Don't look at his lips. Look at me. I'm the talent here.")
            end
            v.nextLineAt=current+18000
        end
    end
    return true,v.stage
end
function Morton.intentFor(a,p,s,g)
    local v=story(g)
    if not v then return nil end
    if g.standing=="Hostile" then return {mode="hostile",priority=110} end
    local threats=s and (tonumber(s.threatCount) or #(s.threats or {})) or 0
    if threats>0 then
        if SC.NativeActions then SC.NativeActions.leaveSeating(a) end
        return {mode="zombie_defense",priority=18}
    end
    return {mode="morton_sit",priority=38}
end
function Morton.update(a,p,r,intent,g)
    if not intent or intent.mode~="morton_sit" then return false,"not_seating" end
    local object=chair(story(g))
    if not object then return false,"stage_chair_unavailable" end
    if select(1,U().call(a,"isSittingOnFurniture"))==true then
        return true,"morton_seated" end
    local arrived,targets=U().directInteractionAccess(a,object)
    if not arrived then
        if not SC.Navigation or not SC.Navigation.requestAny or #targets==0 then
            return false,"stage_chair_blocked" end
        return SC.Navigation.requestAny(a,targets,"walk",{
            action="morton_approach_chair",object=object,
            targetSquare=U().squareOf(object),requireSameSquare=true,
            continuousApproach=true })
    end
    return U().move(a,"walk",{action="sit",object=object,
        targetSquare=U().squareOf(object)})
end
function Morton.canRecruit(g)
    local v=story(g)
    return v and v.stage=="together" and g.standing=="Trusted" or false,
        "refuse_to_split_the_pair"
end
function Morton.menuOptions(g,p)
    local v=story(g)
    if not v or not near(g,p) then return {} end
    local options={}
    if v.stage=="performing" then
        options[#options+1]={id="visit",label="Stay for another show",
            enabled=true}
        if bloodOnPlayer(p) or raccoonNear(actorFor(g))
            or costumeNear(actorFor(g)) then
            options[#options+1]={id="roast",label="Ask Buster what he sees",
                enabled=true}
        end
    elseif v.stage=="choice" then
        options[#options+1]={id="take_buster",label="Take Buster away",
            enabled=doll(actorFor(g))~=nil}
        options[#options+1]={id="refuse",label="Keep Morton and Buster together",
            enabled=true}
    elseif v.stage=="together" then
        options[#options+1]={id="recruit",label="Invite both voices",
            enabled=Morton.canRecruit(g)==true}
    end
    return options
end
function Morton.action(g,action,p)
    local v=story(g)
    if not v then return false,"wrong_oddball" end
    if action=="hurt" then return SC.Factions.forceStanding(g.id,"Hostile") end
    if not near(g,p) then return false,"stage_too_far" end
    local a=actorFor(g)
    if action=="visit" and v.stage=="performing" then
        local clock=type(getGameTime)=="function" and getGameTime()
        local hours=clock and select(1,U().call(clock,"getWorldAgeHours"))
        local day=hours and math.floor(hours/24)
        if not day or v.lastVisitDay==day then
            return false,"come_back_tomorrow" end
        v.lastVisitDay=day
        v.visits=(tonumber(v.visits) or 0)+1
        if v.visits>=3 then
            v.stage="choice"
            sayBuster(a,"Take me with you. Leave him here. He won't even notice.")
            U().say(a,"Morton: He doesn't mean it. He never means it. Do you, Buster?")
        else
            U().say(a,"Morton: Come back tomorrow. I'll have a new act.")
        end
        return true,"real_visit_recorded"
    end
    if action=="roast" and v.stage=="performing" then
        if bloodOnPlayer(p) then
            sayBuster(a,"Nice shirt. Was it red when you bought it?")
        elseif costumeNear(a) then
            sayBuster(a,"Love the costume. Dressing for the job you want? Corpse?")
        elseif raccoonNear(a) then
            sayBuster(a,"Is that a raccoon, or did somebody's hat come to life?")
        else return false,"nothing_to_roast" end
        return true,"visible_roast"
    end
    if action=="take_buster" and v.stage=="choice" then
        local puppet=doll(a)
        local source=puppet and select(1,U().call(puppet,"getContainer"))
        U().call(a,"setPrimaryHandItem",nil)
        if not source or not U().transferItemVerified(source,U().inventory(p),puppet)
            then
            if puppet then U().call(a,"setPrimaryHandItem",puppet) end
            return false,"buster_transfer_failed" end
        v.stage="silent"
        U().say(a,"Morton: Buster? Buster, say something. ...Please say something.")
        return true,"buster_really_taken"
    end
    if action=="refuse" and v.stage=="choice" then
        v.stage="together"
        SC.Factions.forceStanding(g.id,"Trusted")
        sayBuster(a,"You stayed. Morton, I like this one.")
        return true,"pair_kept_together"
    end
    if action=="recruit" and Morton.canRecruit(g)==true
        and SC.FactionRecruitment then
        local asked,reason=SC.FactionRecruitment.ask(g.id,p,false)
        if not asked then return false,reason end
        sayBuster(a,"Fine, we'll come. But I ride up front, and he carries me.")
        return SC.FactionRecruitment.startTrial(g.id,p,false)
    end
    return false,"stage_choice_unavailable"
end
return Morton
