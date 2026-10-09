-- SPDX-License-Identifier: MIT
-- A generator lesson trades exact native components for the vanilla magazine.
-- The screwdriver is assigned through the ordinary personal-item lifecycle.
local SC=SurvivorCompanion
SC.OddballGrinder=SC.OddballGrinder or {}
local Grinder=SC.OddballGrinder
local ID="grinder_berg"
local PARTS={ ["Base.ElectronicsScrap"]=10,
    ["Base.ElectricWire"]=2,["Base.Battery"]=4 }
local LINES={
    "Grinder Berg. Twelve years wiring the enrichment plant in Paducah. Ask me anything.",
    "Chernobyl, '86. They ran a safety test. The safety test did it.",
    "Three Mile Island. Valve stuck open; the panel light said closed. Never trust a light.",
    "Browns Ferry, '75. Fella checked for air leaks with a candle. A candle!",
    "SL-1, Idaho, '61. One control rod pulled too far. Three men. Bad day.",
    "Slotin kept the shells apart with a screwdriver in '46. It slipped. Mine never slips.",
    "Windscale caught fire in '57. They put it out with water. Brave or stupid. Both.",
    "Fermi One, '66. A loose piece of metal blocked the coolant. Nearly lost Detroit.",
    "Paducah's two hundred miles west. Still enriching, far as I know. Probably fine.",
    "Still got juice. Tingles. Nine volts will tell you more than a panel light.",
    "Radiation? Somebody scrammed too late. Mark my words.",
    "Crowbar's the only tool that's also a philosophy. If it hums, hit it harder.",
}
local function U() return SC.GameplayUtil end
local function story(g)
    local v=g and g.oddball
    if type(v)~="table" or v.id~=ID then return nil end
    v.stage=v.stage or "radio_workbench"
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
local function itemFor(a,kind,tag)
    local inv=a and U().inventory(a)
    for _,item in ipairs(inv and U().inventoryItemsDeep(inv,280,10) or {}) do
        if U().itemType(item)==kind
            and (not tag or (U().modData(item) or {})[tag]) then
            return item end
    end
end
local function supply(a,kind,count)
    local made=0
    for _=1,count do
        local item=U().addItem(U().inventory(a),kind)
        if item then
            local data=U().modData(item)
            if data then data.lfGrinderStock=true end
            made=made+1
        end
    end
    return made
end
local function nearbyOddball(actor,id)
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
function Grinder.onSpawn(g,a)
    local v=story(g)
    if not v or not a then return false,"electrician_unavailable" end
    local inv=U().inventory(a)
    if not inv then return false,"inventory_unavailable" end
    if not v.gearSeeded then
        local crowbar=itemFor(a,"Base.Crowbar") or U().addItem(inv,"Base.Crowbar")
        local vodka=U().addItem(inv,"Base.Vodka")
        if vodka then
            local data=U().modData(vodka)
            if data then data.lfGrinderMeltdown=true end
        end
        if crowbar and vodka then v.gearSeeded=true end
    end
    local bar=itemFor(a,"Base.Crowbar")
    if bar then U().call(a,"setPrimaryHandItem",bar) end
    if not v.stockSeeded then
        local amount=supply(a,"Base.Battery",3)
            + supply(a,"Base.ElectricWire",2)
            + supply(a,"Base.ElectronicsScrap",5)
        if amount>0 then v.stockSeeded=true end
    end
    return v.gearSeeded==true,"grinder_real_gear_ready"
end
function Grinder.pulse(g,p,current)
    local v=story(g)
    if not v then return false,"wrong_oddball" end
    local a=actorFor(g)
    if not a then return false,"electrician_unloaded" end
    current=tonumber(current) or U().nowMs()
    if near(g,p) and not v.greeted then
        v.greeted=true
        g.discovered=true
        U().say(a,LINES[1])
    end
    if near(g,p) and current>=(tonumber(v.nextCrosslinkAt) or 0) then
        v.nextCrosslinkAt=current+30000
        local gordon=not v.gordonRemark and nearbyOddball(a,"gordon_pettibone")
        local mien=not v.mienRemark and nearbyOddball(a,"mien_ward")
        if gordon then
            v.gordonRemark=true
            U().say(a,"A reactor isn't a bomb, Gordon. It's a very serious kettle.")
            U().say(gordon,"That's what they told me about the last kettle.")
        elseif mien then
            v.mienRemark=true
            U().say(a,"Not now, Mien. I'm counting the batteries.")
            U().say(mien,"Four batteries? That's nearly enough for a brewery.")
        end
    end
    return true,v.stage
end
function Grinder.pulseRecruited(g,a)
    local bar=a and itemFor(a,"Base.Crowbar")
    if bar then U().call(a,"setPrimaryHandItem",bar) end
    return bar~=nil,"crowbar_still_carried"
end
function Grinder.intentFor(a,p,s,g)
    if not story(g) then return nil end
    if g.standing=="Hostile" then return {mode="hostile",priority=110} end
    local threats=s and (tonumber(s.threatCount) or #(s.threats or {})) or 0
    if threats>0 then return {mode="zombie_defense",priority=18} end
    return {mode="oddball_idle",priority=28}
end
function Grinder.canRecruit(g)
    local v=story(g)
    return v and v.lessonGiven==true and g.standing=="Trusted" or false,
        "complete_the_generator_lesson"
end
function Grinder.menuOptions(g,p)
    local v=story(g)
    if not v or not near(g,p) then return {} end
    local spirit=SC.OddballExchange.select(p,
        {["Base.Whiskey"]=1}) or SC.OddballExchange.select(p,
        {["Base.Vodka"]=1})
    local stock=itemFor(actorFor(g),"Base.ElectricWire","lfGrinderStock")
        or itemFor(actorFor(g),"Base.Battery","lfGrinderStock")
        or itemFor(actorFor(g),"Base.ElectronicsScrap","lfGrinderStock")
    return {
        {id="ask_reactor",label="Ask Grinder about reactor accidents",
            enabled=true},
        {id="ask_screwdriver",label="Ask about the lucky screwdriver",
            enabled=true},
        {id="generator_lesson",label="Bring ten scrap, two wire and four batteries",
            enabled=not v.lessonGiven and
                SC.OddballExchange.select(p,PARTS)~=nil},
        {id="trade_spirit",label="Trade spirits for spare electric parts",
            enabled=spirit~=nil and stock~=nil},
        {id="recruit",label="Invite Grinder to camp",
            enabled=Grinder.canRecruit(g)==true},
    }
end
function Grinder.action(g,action,p)
    local v=story(g)
    if not v then return false,"wrong_oddball" end
    if action=="hurt" then return SC.Factions.forceStanding(g.id,"Hostile") end
    if not near(g,p) then return false,"workbench_too_far" end
    local a=actorFor(g)
    if action=="ask_reactor" then
        v.line=((tonumber(v.line) or 0)%(#LINES-1))+2
        U().say(a,LINES[v.line])
        return true,"reactor_story"
    end
    if action=="ask_screwdriver" then
        U().say(a,U().config("profanityEnabled")==false
            and "Nobody touches the screwdriver. Not you, not God, not the dead."
            or "Nobody touches the screwdriver. Not you, not God, not the goddamn dead.")
        return true,"keepsake_guarded"
    end
    if action=="generator_lesson" and not v.lessonGiven then
        local moved,entries=SC.OddballExchange.take(p,a,PARTS)
        if not moved then return false,entries end
        local inv=U().inventory(a)
        local magazine=U().addItem(inv,"Base.ElectronicsMag4")
        if not magazine then
            SC.OddballExchange.returnMoved(a,entries)
            return false,"generator_magazine_unavailable"
        end
        if not U().transferItemVerified(inv,U().inventory(p),magazine) then
            U().call(inv,"Remove",magazine)
            SC.OddballExchange.returnMoved(a,entries)
            return false,"generator_magazine_transfer_failed"
        end
        v.lessonGiven=true
        SC.Factions.forceStanding(g.id,"Trusted")
        U().say(a,"Read this. Ground the generator before you touch it.")
        return true,"real_generator_manual_delivered"
    end
    if action=="trade_spirit" then
        local payment=SC.OddballExchange.select(p,
            {["Base.Whiskey"]=1}) or SC.OddballExchange.select(p,
            {["Base.Vodka"]=1})
        local spare=itemFor(a,"Base.ElectricWire","lfGrinderStock")
            or itemFor(a,"Base.Battery","lfGrinderStock")
            or itemFor(a,"Base.ElectronicsScrap","lfGrinderStock")
        if not payment or not spare then return false,"spirit_or_stock_missing" end
        local item=payment[1]
        local source=select(1,U().call(item,"getContainer"))
        local stock=select(1,U().call(spare,"getContainer"))
        if not source or not stock then return false,"trade_container_missing" end
        if not U().transferItemVerified(source,U().inventory(a),item) then
            return false,"spirit_transfer_failed" end
        if not U().transferItemVerified(stock,U().inventory(p),spare) then
            U().transferItemVerified(U().inventory(a),source,item)
            return false,"electrical_part_transfer_failed"
        end
        v.trades=(tonumber(v.trades) or 0)+1
        SC.Factions.adjustStanding(g.id,8,"electrical_spirit_trade")
        U().say(a,"Saving that for the meltdown. Here's something useful.")
        return true,"real_electrical_trade"
    end
    if action=="recruit" and Grinder.canRecruit(g)==true
        and SC.FactionRecruitment then
        local asked,reason=SC.FactionRecruitment.ask(g.id,p,false)
        if not asked then return false,reason end
        U().say(a,"Fine. Crowbar, screwdriver, vodka. In that order.")
        return SC.FactionRecruitment.startTrial(g.id,p,false)
    end
    return false,"electrician_choice_unavailable"
end
return Grinder
