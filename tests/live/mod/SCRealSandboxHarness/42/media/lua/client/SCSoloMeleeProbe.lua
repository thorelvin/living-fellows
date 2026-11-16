-- SPDX-License-Identifier: MIT
-- Live field trials: one real watched LF companion, fourteen ordinary melee
-- weapons, 0..5 native zombies. Only initial companion detection is seeded.
-- No mid-fight stat changes, zombie steering, artificial collisions or damage.
local Probe = {}
local PIN = {x=6444,y=5461,z=0}
local FILE = "SurvivorCompanionHarness/solo-melee-results.txt"
local WEAPONS = {
    {"Base.Crowbar","Crowbar"}, {"Base.BaseballBat","BaseballBat"},
    {"Base.Axe","Axe"}, {"Base.HandAxe","HandAxe"},
    {"Base.WoodAxe","WoodAxe"}, {"Base.Machete","Machete"},
    {"Base.HuntingKnife","HuntingKnife"}, {"Base.Hammer","Hammer"},
    {"Base.LeadPipe","LeadPipe"}, {"Base.SpearCrafted","CraftedSpear"},
    {"Base.Plank","Plank"}, {"Base.Sledgehammer","Sledgehammer"},
    {"Base.Wrench","Wrench"}, {"Base.KitchenKnife","KitchenKnife"},
}
function Probe.trialTimeoutMs(config)
    local seconds=tonumber(config and config.solo_melee_trial_seconds) or 90
    if seconds~=seconds then seconds=90 end
    return math.max(30,math.min(300,seconds))*1000
end
function Probe.withdrawalComplete(episodeSeconds,episodeDistance,maxDisplacement)
    return episodeSeconds>=5 and episodeDistance>=8 and maxDisplacement>26
end
function Probe.receiptToken(runId,caseIndex,started,index)
    return tostring(runId) .. ":" .. tostring(caseIndex) .. ":" .. tostring(started) .. ":" .. tostring(index)
end
function Probe.weaponForCase(index)
    index=tonumber(index)
    if not index or index~=math.floor(index) or index<1 or index>#WEAPONS*6 then return nil end
    return WEAPONS[math.floor((index-1)/6)+1],(index-1)%6
end
local COLUMNS = {"case","weapon","zombies","outcome","kills","health","lowest_health","bites","seconds",
    "endurance_start","endurance_end","condition_start","condition_end","melee_skill","maintenance_skill",
    "native_min_range","native_max_range","accepted_min_range","accepted_max_range",
    "native_contacts","accepted_damage_events","health_loss_observed","impacts_backward","damage_backward",
    "contacts_beyond_native_range","contacts_beyond_tolerance","contacts_behind_facing","impacts_unknown_motion",
    "collision_events","empty_collisions","evidence_landed","evidence_no_effect","shoves","stomps",
    "kite_seconds","backward_seconds","attack_backward_seconds","retreat_seconds","retreat_episodes","overrun_seconds",
    "max_displacement","max_still_seconds","minimum_player_distance","swing_sounds","unexpected_weapon_samples",
    "minimum_hit_distance","maximum_hit_distance","actions","retreat_causes",
    "lowest_endurance","model_skill","model_perk","weapon_broken","final_held_type",
    "initial_model_skill","initial_model_perk","max_retreat_episode_seconds","max_retreat_episode_distance"}
local function call(o,m,...)
    if o==nil then return nil end
    local okay,value=pcall(function(...) return o[m](o,...) end,...)
    if okay then return value end
    return nil
end
local function num(v,d) return tonumber(tostring(v)) or d or 0 end
local function alive(a) return a and call(a,"isDead")==false
    and SurvivorCompanion.GameplayUtil.nativeHealth(a)>0 end
local function format(v) return string.format("%.2f",num(v)) end
local function point(a)
    local x,y,z=SurvivorCompanion.GameplayUtil.position(a)
    return {x=x,y=y,z=z}
end
local function distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
local function square(x,y)
    return SurvivorCompanion.GameplayUtil.gridSquare(math.floor(x),math.floor(y),0)
end
local function free(x,y,indoors)
    local s=square(x,y)
    return s and call(s,"TreatAsSolidFloor")==true
        and SurvivorCompanion.GameplayUtil.isSquareFree(s)
        and (indoors==nil or (call(s,"getRoom")~=nil)==indoors) and s or nil
end
local function photo(H,label)
    pcall(function()
        local SC=SurvivorCompanion
        if SC.UI and SC.UI.instance then call(SC.UI.instance,"setVisible",false) end
        for slot=0,(getSpecificPlayer(1) and 1 or 0) do
            call(getPlayerInfoPanel(slot),"setVisible",false)
            call(getPlayerInventory(slot),"setVisible",false)
            call(getPlayerLoot(slot),"setVisible",false)
            call(getPlayerMiniMap(slot),"setVisible",false)
            getCore():setAutoZoom(slot,false)
            for _=1,8 do if getCore():getZoom(slot)<2.5 then getCore():doZoomScroll(slot,1) end end
        end
        getCore():TakeFullScreenshot(H.config.run_id .. "-melee-" .. label .. ".png")
    end)
end
local function writeRows(H)
    local writer=getFileWriter(FILE,true,false)
    if not writer then return false end
    writer:writeln(table.concat(COLUMNS,","))
    for _,row in ipairs(H.melee.rows) do
        local fields={}
        for _,name in ipairs(COLUMNS) do fields[#fields+1]=tostring(row[name] or "") end
        writer:writeln(table.concat(fields,","))
    end
    writer:close()
    return true
end
local function geometry(s)
    local U=SurvivorCompanion.GameplayUtil
    local arena,direction,indoor
    if not s.siteCandidates then
        s.siteCandidates={};s.siteCursor=1
        for dy=-60,60,4 do for dx=-60,60,4 do
            s.siteCandidates[#s.siteCandidates+1]={dx,dy}
        end end
        table.sort(s.siteCandidates,function(a,b) return a[1]^2+a[2]^2 < b[1]^2+b[2]^2 end)
    end
    -- At most two candidate centres per work pulse; do not stall the desktop
    -- while inspecting a larger open footprint than the original spawn lane.
    for _=1,2 do
        local offset=s.siteCandidates[s.siteCursor];s.siteCursor=s.siteCursor+1
        if not offset then return nil,"no open 24-metre combat footprint near requested field" end
            local x,y=PIN.x+offset[1],PIN.y+offset[2]
            local clear=free(x,y,false)~=nil
            if clear then for ray=0,15 do
                local px,py=x,y
                for step=1,24 do
                    local nx=math.floor(x+math.cos(ray*math.pi/8)*step+0.5)
                    local ny=math.floor(y+math.sin(ray*math.pi/8)*step+0.5)
                    local a,b=free(px,py,false),free(nx,ny,false)
                    if not a or not b or U.edgeBlocked(a,b) then clear=false;break end
                    px,py=nx,ny
                end
                if not clear then break end
            end end
            if clear then for _,d in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
                local lane=true
                for i=1,10 do
                    local depth,lateral=12+math.floor((i-1)/5)*2,(i-1)%5-2
                    lane=lane and free(x+d[1]*depth-d[2]*lateral,y+d[2]*depth+d[1]*lateral,false)~=nil
                end
                for back=1,6 do lane=lane and free(x-d[1]*back,y-d[2]*back,false)~=nil end
                for depth=1,16 do for lateral=-2,2 do
                    local previous=free(x+d[1]*(depth-1)-d[2]*lateral,y+d[2]*(depth-1)+d[1]*lateral,false)
                    local nextSquare=free(x+d[1]*depth-d[2]*lateral,y+d[2]*depth+d[1]*lateral,false)
                    lane=lane and previous and nextSquare and not U.edgeBlocked(previous,nextSquare)
                end end
                if lane then arena,direction={x=x+0.5,y=y+0.5,z=0},d; break end
            end end
        if arena then break end
    end
    if not arena then return nil,"searching" end
    local nearest=math.huge
    for y=PIN.y-55,PIN.y+55 do for x=PIN.x-55,PIN.x+55 do
        local s=free(x,y,true)
        if s then local d=(x-arena.x)^2+(y-arena.y)^2
            if d<nearest then indoor,nearest=s,d end end
    end end
    if not indoor then return nil,"no loaded indoor Base Watch enrollment square" end
    local observer
    for back=60,40,-1 do
        for _,d in ipairs({{-direction[1],-direction[2]}, {-direction[2],direction[1]},
            {direction[2],-direction[1]}, {direction[1],direction[2]}, {0.707,0.707}, {-0.707,-0.707}}) do
            local x,y=arena.x+d[1]*back,arena.y+d[2]*back
            if free(x,y) then observer={x=math.floor(x)+0.5,y=math.floor(y)+0.5,z=0}; break end
        end
        if observer then break end
    end
    if not observer then return nil,"no distant observer square near " .. arena.x .. ":" .. arena.y end
    return {arena=arena,direction=direction,indoor=indoor,observer=observer}
end
local function cleanup(SC,s)
    if s.motionObserver then Events.OnTick.Remove(s.motionObserver);s.motionObserver=nil end
    if s.deathObserver then Events.OnZombieDead.Remove(s.deathObserver); s.deathObserver=nil end
    if s.hitObserver then Events.OnHitZombie.Remove(s.hitObserver); s.hitObserver=nil end
    if s.damageObserver then Events.OnWeaponHitXp.Remove(s.damageObserver); s.damageObserver=nil end
    for _,receipt in ipairs(s.zombies or {}) do
        if not receipt.dead then call(receipt.actor,"removeFromWorld"); call(receipt.actor,"removeFromSquare") end
    end
    s.zombies={}
    -- Keep the watched chunk active until native death has made its corpse.
    -- Releasing the second map first can suspend a just-dying actor forever.
    if s.actor and not alive(s.actor) and call(s.actor,"isCorpseReady")~=true then
        return false,"native corpse animation pending"
    end
    if SC.BaseWatch.current() then
        -- These are independent cloned-world trials. Use the owned-view
        -- teardown, including an observer who has left the small home area.
        local okay,why=SC.BaseWatch.prepareReset()
        if not okay then return false,"view release: " .. tostring(why) end
        SC.BaseWatch.reset()
    end
    if getSpecificPlayer(1)~=nil or SC.ViewSession.owner()~=nil then return false,"view ownership pending" end
    if s.actor and SC.Actor._isRegistryActor(s.actor) then
        local okay,why
        if alive(s.actor) then
            okay,why=SC.Actor.remove(s.actor)
        else
            okay,why=SC.Actor.retireDead(s.actor)
        end
        if okay==false then return false,"actor release: " .. tostring(why) end
    end
    s.actor=nil
    return true
end
function Probe.removeBody(body)
    local sq=call(body,"getSquare")
    if not sq then return false end
    -- IsoDeadBody is in the square's static list. Inherited moving-object
    -- removal can leave that entry rendered and active in later trials.
    local ok=pcall(function() sq:removeCorpse(body,false) end)
    if not ok then return false end
    local entries=call(sq,"getStaticMovingObjects")
    local count=num(call(entries,"size"),-1)
    if count<0 or count>128 then return false end
    for index=0,count-1 do if call(entries,"get",index)==body then return false end end
    return true
end
local function clearBodies(s)
    local U=SurvivorCompanion.GameplayUtil
    local removed,failed,loaded=0,0,0
    for y=math.floor(s.arena.y)-22,math.floor(s.arena.y)+22 do
        for x=math.floor(s.arena.x)-22,math.floor(s.arena.x)+22 do
            local bodies={}
            local sq=square(x,y)
            if sq then loaded=loaded+1 end
            U.squareStaticMovingObjects(sq,function(o)
                if U.instanceOf(o,"IsoDeadBody") then bodies[#bodies+1]=o end
            end,16)
            for _,body in ipairs(bodies) do
                if Probe.removeBody(body) then removed=removed+1 else failed=failed+1 end
            end
        end
    end
    return failed==0 and loaded==2025,removed,loaded
end

local function equip(SC,s,H)
    local a=s.actor
    getGameTime():setTimeOfDay(12)
    for _,key in ipairs({"Strength","Fitness"}) do a:setPerkLevelDebug(Perks[key],5) end
    for _,key in ipairs({"Blunt","SmallBlunt","Axe","LongBlade","SmallBlade","Spear","Maintenance"}) do
        if not Perks[key] then return false,"missing perk " .. key end
        a:setPerkLevelDebug(Perks[key],3)
        if num(call(a,"getPerkLevel",Perks[key]),-1)~=3 then return false,"perk readback failed: " .. key end
    end
    local stats=a:getStats()
    for key,value in pairs({ENDURANCE=1,FATIGUE=0,HUNGER=0.1,THIRST=0.05,PANIC=0}) do
        stats:set(CharacterStat[key],value)
    end
    local inv=a:getInventory()
    a:setPrimaryHandItem(nil);a:setSecondaryHandItem(nil)
    for _,item in ipairs(SC.GameplayUtil.inventoryItems(inv,128)) do
        call(a,"removeWornItem",item);inv:Remove(item)
    end
    for _,kind in ipairs({"Base.Tshirt_DefaultTEXTURE_TINT","Base.Trousers_Denim","Base.Shoes_TrainerTINT"}) do
        local item=inv:AddItem(kind)
        if not item then return false,"standard clothing missing: " .. kind end
        a:setWornItem(item:getBodyLocation(),item)
    end
    s.item=inv:AddItem(s.weapon[1])
    if not s.item or call(s.item,"isRanged")~=false then return false,"melee item missing" end
    s.item:setCondition(s.item:getConditionMax())
    a:setPrimaryHandItem(s.item)
    if call(s.item,"isTwoHandWeapon")==true then a:setSecondaryHandItem(s.item) end
    local _,_,record=SC.Combat.meleeRange(a,s.item)
    s.initialModel=SC.Combat.readiness(a,{threats={},allies={},escapeSquares={}},record,{})
    for _,order in ipairs({{"set_combat_doctrine","weapons_free"},{"set_weapon_priority","melee"},{"stay"}}) do
        local ok,why=SC.Commands.issue(SC.Registry.idOf(a),order[1],order[2],s.player)
        if not ok then return false,why end
    end
    return true
end
local function histogram(t)
    local keys={};for key in pairs(t) do keys[#keys+1]=key end;table.sort(keys)
    local out={};for _,key in ipairs(keys) do out[#out+1]=key .. ":" .. format(t[key]) end
    return table.concat(out,"|")
end
local function writeTrace(s,suffix,header,rows)
    -- PZ's Lua file API accepts .txt here, not arbitrary .csv names. The
    -- contents are CSV; the audit exporter supplies the .csv extension.
    local writer=getFileWriter("SurvivorCompanionHarness/solo-melee-case-" .. s.case .. "-" .. suffix .. ".txt",true,false)
    if not writer then return false end
    writer:writeln(header)
    for _,row in ipairs(rows) do writer:writeln(table.concat(row,",")) end
    writer:close();return true
end
local function facing(a)
    local v=call(a,"getForwardDirection")
    return num(call(v,"getX"),1),num(call(v,"getY"),0)
end
local function movingBack(s,now)
    local m=s.motion
    if not m or now-m.at>100 or m.dt<=0 or m.dt>100 then return nil end
    local fx,fy=facing(s.actor)
    return m.dx*fx+m.dy*fy < -0.001
end
function Probe.step(H,current,check,result,setPhase)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    if SC.UI and SC.UI.instance then SC.UI.close() end
    pcall(function()
        for slot=0,(getSpecificPlayer(1) and 1 or 0) do
            call(getPlayerInfoPanel(slot),"setVisible",false)
            call(getPlayerInventory(slot),"setVisible",false)
            call(getPlayerLoot(slot),"setVisible",false)
            call(getPlayerMiniMap(slot),"setVisible",false)
            getCore():setAutoZoom(slot,false)
            if getCore():getZoom(slot)<2.5 then getCore():doZoomScroll(slot,1) end
        end
    end)
    H.melee=H.melee or {rows={},index=num(H.config.solo_melee_start_case,1),last=num(H.config.solo_melee_end_case,60)}
    local s=H.melee
    if not s.selected then
        s.selected={}
        for value in string.gmatch(tostring(H.config.solo_melee_cases or ""),"%d+") do
            s.selected[#s.selected+1]=tonumber(value)
        end
        if #s.selected>0 then s.cursor=1;s.index=s.selected[1];s.last=#WEAPONS*6 end
    end
    local function fail(name,detail)
        photo(H,"blocked-" .. s.index .. "-" .. name)
        result("FAIL","melee_" .. name,tostring(detail))
        s.failure=current;setPhase("solo_melee_failed",current)
    end
    if H.phase=="solo_melee_failed" then
        if current-s.failure>2000 and cleanup(SC,s) then setPhase("finish",current) end
        return
    end
    if H.phase=="solo_melee_load" then
        if not s.loadAt then
            -- Isolate the measured companion from ordinary LF arrivals. These
            -- overrides belong only to this disposable process/save clone.
            local sandbox=type(SandboxVars)=="table" and SandboxVars.LivingFellows
            local options={EncountersEnabled="productionEncounterEnabled",FirstMeetingEnabled="firstMeetingEnabled",
                HouseholdSpawnsEnabled="factionEnabled",OddballsEnabled="oddballsEnabled",BanditCampsEnabled="banditFactionEnabled"}
            for option,key in pairs(options) do
                if sandbox then sandbox[option]=false end
                SC.Config._overrides[key]=false
            end
            for _,a in ipairs(SC.Registry.living()) do SC.Actor.remove(a) end
            result("PASS","melee_population_isolated","background LF arrivals disabled; native zombie behaviour unchanged")
            H.player:teleportTo(PIN.x+0.5,PIN.y+0.5,0)
            s.loadAt=current;return
        end
        if current-s.loadAt<10000 then return end
        local geo,why=geometry(s)
        if not geo and why=="searching" then return end
        if not geo then return fail("geometry",why) end
        for key,value in pairs(geo) do s[key]=value end
        if not writeRows(H) then return fail("results_write",FILE) end
        s.player=H.player
        getGameTime():setTimeOfDay(12)
        photo(H,"site-setup")
        result("PASS","melee_site","requested=6444:5461 arena=" .. format(s.arena.x) .. ":" .. format(s.arena.y)
            .. " observer=" .. format(s.observer.x) .. ":" .. format(s.observer.y) .. " melee=3 maintenance=3 strength=5 fitness=5")
        setPhase("solo_melee_prepare",current);return
    end
    if H.phase=="solo_melee_prepare" then
        if s.index>s.last then
            result("PASS","melee_matrix_recorded","trials=" .. #s.rows .. " file=" .. FILE .. " outcomes are measurements, not guaranteed wins")
            setPhase("finish",current);return
        end
        if getSpecificPlayer(1) or SC.BaseWatch.current() then return fail("view_not_released",s.index) end
        SC.BaseLife.reset()
        getGameTime():setTimeOfDay(12)
        H.clearZombiesNear(square(s.arena.x,s.arena.y),150)
        H.clearZombiesNear(H.player,60)
        s.case=s.index
        s.removedBodies=0
        s.weapon,s.count=Probe.weaponForCase(s.case)
        if not s.weapon then return fail("case_number",s.case) end
        -- Releasing a distant watched map can unload the range. Bring the
        -- primary map here and wait for its real squares before asking to spawn.
        H.player:teleportTo(s.arena.x+3,s.arena.y,0)
        setPhase("solo_melee_spawn",current);return
    end
    if H.phase=="solo_melee_spawn" then
        local rangeSquare=square(s.arena.x,s.arena.y)
        local indoorSquare=square(s.indoor:getX(),s.indoor:getY())
        if current-H.phaseStartedAt<1500 or not rangeSquare or not indoorSquare then
            if current-H.phaseStartedAt>15000 then return fail("range_load","range/indoor squares not loaded") end
            return
        end
        s.indoor=indoorSquare
        H.player:setCurrentSquare(square(s.arena.x+3,s.arena.y))
        H.clearZombiesNear(rangeSquare,150)
        -- Releasing Base Watch unloads the field before the primary map moves
        -- back here. Cleaning in prepare silently visits absent squares.
        local floorClean,removed,loaded=clearBodies(s)
        s.removedBodies=s.removedBodies+removed
        if not floorClean then
            if loaded<2025 and current-H.phaseStartedAt<15000 then return end
            return fail("corpse_cleanup","native removal/readback failed; loaded=" .. loaded)
        end
        result("PASS","melee_floor_clean","case=" .. s.index .. " removed=" .. s.removedBodies .. " loaded=" .. loaded)
        local ticket,why=SC.Actor.beginSpawn(square(s.arena.x,s.arena.y),{recruited=true,
            background={profession="unemployed",aptitude="fast_learner",abilitySeed="solo-melee-skill3"},
            state={personality={version=2,courage=60,caution=50,compassion=50,practicality=50}},
            identity={forename="Range",surname=s.weapon[2],gender="woman",outfit="Generic01",visualSeed=2719}})
        s.ticket=ticket
        if not s.ticket then return fail("actor_spawn",why) end
        setPhase("solo_melee_poll",current);return
    end
    if H.phase=="solo_melee_poll" then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then
            if why~="spawn_pending" or current-H.phaseStartedAt>15000 then return fail("actor_spawn",why) end
            return
        end
        s.actor=actor
        local okay,why=equip(SC,s,H)
        if not okay then return fail("equipment",why) end
        s.actor:teleportTo(s.indoor:getX()+0.5,s.indoor:getY()+0.5,0)
        s.actor:setCurrentSquare(s.indoor)
        H.player:teleportTo(s.indoor:getX()+0.5,s.indoor:getY()+0.5,0)
        H.player:setCurrentSquare(s.indoor)
        okay,why=SC.BaseLife.create(s.indoor,"Solo melee test camp")
        if not okay then return fail("camp",why) end
        SC.BaseLife.beginZone("area",{x=math.floor(s.arena.x)-8,y=math.floor(s.arena.y)-8,z=0})
        okay,why=SC.BaseLife.finishZone({x=math.floor(s.arena.x)+8,y=math.floor(s.arena.y)+8,z=0},"Melee area")
        if not okay then return fail("camp_area",why) end
        SC.BaseLife.assign(SC.Registry.idOf(actor),"guard",true)
        -- Camera-only staging. Preserve the native Stay anchor at the range;
        -- Base Watch's duty precondition is satisfied in this synchronous call.
        local commands=SC.Commands.peek(actor)
        local previous=commands.order;commands.order="base_duty"
        local called,started,watchWhy=pcall(SC.BaseWatch.start,SC.Registry.idOf(actor))
        commands.order=previous
        if not called or not started then return fail("base_watch",watchWhy or started) end
        setPhase("solo_melee_join",current);return
    end
    if H.phase=="solo_melee_join" then
        if getSpecificPlayer(1)~=s.actor then
            if current-H.phaseStartedAt>15000 then return fail("base_watch_join","native slot 1 not ready") end
            return
        end
        s.actor:teleportTo(s.arena.x,s.arena.y,0)
        s.actor:setCurrentSquare(square(s.arena.x,s.arena.y))
        H.player:teleportTo(s.observer.x,s.observer.y,0)
        H.player:setCurrentSquare(square(s.observer.x,s.observer.y))
        s.readyAt=current+1500
        setPhase("solo_melee_ready",current);return
    end
    if H.phase=="solo_melee_ready" then
        if current<s.readyAt then return end
        local members=SC.Registry.living()
        if #members~=1 or members[1]~=s.actor then return fail("sole_fighter","unexpected additional LF actors") end
        if distance(point(s.actor),s.arena)>1.5 then return fail("actor_position","left the range before spawning") end
        if getSpecificPlayer(0)~=H.player or getSpecificPlayer(1)~=s.actor
            or not alive(H.player) or distance(point(s.actor),point(H.player))<20 then return fail("observer_position","view ownership/clearance") end
        s.visionModifier=num(call(s.actor,"getWornItemsVisionModifier"),-1)
        if math.abs(s.visionModifier-1)>0.001 then return fail("standard_clothing","unexpected native vision modifier " .. s.visionModifier) end
        s.startTimeOfDay=num(call(getGameTime(),"getTimeOfDay"),-1)
        H.clearZombiesNear(square(s.arena.x,s.arena.y),150)
        s.started=current;s.nextSample=current;s.previousSample=current;s.zombies={};s.kills=0
        s.samples={};s.impacts={};s.actions={};s.causes={};s.lowestHealth=100
        s.retreatSeconds=0;s.retreatEpisodes=0;s.wasRetreating=false;s.overrunSeconds=0
        s.retreatStarted=nil;s.retreatOrigin=nil;s.maxRetreatEpisodeSeconds=0;s.maxRetreatEpisodeDistance=0
        s.kiteSeconds=0;s.backwardSeconds=0;s.attackBackwardSeconds=0
        s.contacts=0;s.accepted=0;s.loss=0;s.backwardImpacts=0;s.backwardDamage=0
        s.outsideNative=0;s.outsideTolerance=0;s.behindFacing=0;s.unknownMotion=0
        s.collisions=0;s.emptyCollisions=0;s.landed=0;s.noEffect=0;s.shoves=0;s.stomps=0
        s.maxDisplacement=0;s.minPlayerDistance=math.huge;s.maxStill=0;s.stillSince=current
        s.unexpectedWeapon=0;s.minHit=math.huge;s.maxHit=0;s.motion=nil;s.lastEvidenceAt=nil
        s.lowestEndurance=1
        s.initialEndurance=num(call(s.actor:getStats(),"get",CharacterStat.ENDURANCE),-1)
        s.initialCondition=num(call(s.item,"getCondition"),-1)
        s.soundStart=num(call(s.actor,"getCompanionSwingSounds"))
        s.lastCollision=num(call(s.actor,"getCompanionAttackCollisionSerial"))
        s.nativeMin=num(call(s.item,"getMinRange"))
        s.nativeMax=num(call(s.item,"getMaxRange",s.actor))*num(call(s.item,"getRangeMod",s.actor),1)
        s.acceptMin,s.acceptMax=SC.Combat.meleeRange(s.actor,s.item)
        s.lastPosition=point(s.actor)
        s.motionObserver=function()
            local now=U.nowMs();local p=point(s.actor);local previous=s.motion
            s.motion={position=p,at=now,dt=previous and now-previous.at or 0,
                dx=previous and p.x-previous.position.x or 0,dy=previous and p.y-previous.position.y or 0}
        end
        Events.OnTick.Add(s.motionObserver)
        s.deathObserver=function(zombie)
            for _,r in ipairs(s.zombies) do if r.actor==zombie and not r.dead then
                r.dead=true;s.kills=s.kills+1
            end end
        end
        Events.OnZombieDead.Add(s.deathObserver)
        -- A contact callback precedes ignored-damage handling. Keep contacts,
        -- accepted damage, sampled health changes and explicit deaths separate.
        s.hitObserver=function(zombie,attacker,part,weapon)
            if attacker~=s.actor then return end
            for i,r in ipairs(s.zombies) do if r.actor==zombie then
                local now=U.nowMs();local p,z=point(attacker),point(zombie)
                local d=distance(p,z);local fx,fy=facing(attacker)
                local dot=d>0 and ((z.x-p.x)*fx+(z.y-p.y)*fy)/d or 1
                local back=movingBack(s,now)
                local shove=call(attacker,"isShoving")==true or call(attacker,"isShoveStompAnim")==true
                local melee=weapon==s.item and not shove
                local combat=SC.Combat.peek(attacker)
                s.impacts[#s.impacts+1]={format((now-s.started)/1000),i,tostring(call(weapon,"getFullType")),
                    tostring(melee),format(d),format(dot),tostring(call(attacker,"isMoving")),tostring(back),
                    format(call(zombie,"getHealth")),"contact",format(p.x),format(p.y),format(z.x),format(z.y),
                    tostring(combat and combat.lastAction),format(s.motion and s.motion.dx),format(s.motion and s.motion.dy),
                    s.motion and s.motion.dt or "",s.motion and now-s.motion.at or ""}
                r.before=num(call(zombie,"getHealth"),r.initialHealth);r.lastBack=back;r.lastMelee=melee
                if melee then
                    s.contacts=s.contacts+1;s.minHit=math.min(s.minHit,d);s.maxHit=math.max(s.maxHit,d)
                    if back==true then s.backwardImpacts=s.backwardImpacts+1 end
                    if back==nil then s.unknownMotion=s.unknownMotion+1 end
                    if d>s.nativeMax+0.01 then s.outsideNative=s.outsideNative+1 end
                    if d>s.acceptMax+0.01 then s.outsideTolerance=s.outsideTolerance+1 end
                    if dot<0 then s.behindFacing=s.behindFacing+1 end
                end
                return
            end end
        end
        Events.OnHitZombie.Add(s.hitObserver)
        s.damageObserver=function(attacker,weapon,zombie,damage)
            if attacker~=s.actor or num(damage)<=0 then return end
            for i,r in ipairs(s.zombies) do if r.actor==zombie then
                local health=num(call(zombie,"getHealth"),r.initialHealth)
                if r.lastMelee and weapon==s.item then
                    s.accepted=s.accepted+1
                    if r.lastBack==true then s.backwardDamage=s.backwardDamage+1 end
                end
                local p,z=point(attacker),point(zombie)
                s.impacts[#s.impacts+1]={format((U.nowMs()-s.started)/1000),i,tostring(call(weapon,"getFullType")),
                    tostring(r.lastMelee),format(distance(p,z)),"",tostring(call(attacker,"isMoving")),tostring(r.lastBack),
                    format(health),"accepted_damage",format(p.x),format(p.y),format(z.x),format(z.y),format(damage),"","","",""}
                return
            end end
        end
        Events.OnWeaponHitXp.Add(s.damageObserver)
        for i=1,s.count do
            local depth,lateral=12,(i-1)-(s.count-1)/2
            local x=s.arena.x+s.direction[1]*depth-s.direction[2]*lateral
            local y=s.arena.y+s.direction[2]*depth+s.direction[1]*lateral
            local list=addZombiesInOutfit(math.floor(x),math.floor(y),0,1,nil,0)
            local z=call(list,"get",0)
            if not z then return fail("zombie_spawn",i) end
            local token=Probe.receiptToken(H.config.run_id,s.case,s.started,i)
            z:getModData().SC_SoloMelee=token
            local health=num(call(z,"getHealth"),1)
            s.zombies[#s.zombies+1]={actor=z,token=token,dead=false,initialHealth=health,lastHealth=health}
            z:spotted(s.actor,true)
        end
        result("PASS","melee_trial_start","case=" .. s.case .. " weapon=" .. s.weapon[2] .. " zombies=" .. s.count
            .. " native_range=" .. format(s.nativeMin) .. ":" .. format(s.nativeMax)
            .. " accepted_range=" .. format(s.acceptMin) .. ":" .. format(s.acceptMax)
            .. " native_view=1 multihit=" .. tostring(SandboxVars.MultiHitZombies))
        if s.count==0 or s.count==5 then photo(H,s.case .. "-" .. s.weapon[2] .. "-setup") end
        setPhase("solo_melee_fight",current);return
    end
    if H.phase=="solo_melee_fight" then
        if current<s.nextSample then return end
        local dt=math.max(0,(current-s.previousSample)/1000)
        s.previousSample=current;s.nextSample=current+100
        if getSpecificPlayer(0)~=H.player or not alive(H.player)
            or getSpecificPlayer(1)~=s.actor then return fail("view_ownership","observer or watched slot changed") end
        local p=point(s.actor);local separation=distance(p,point(H.player))
        s.minPlayerDistance=math.min(s.minPlayerDistance,separation)
        if separation<10 then return fail("observer_clearance","fighter reached observer") end
        s.maxDisplacement=math.max(s.maxDisplacement,distance(p,s.arena))
        s.lowestHealth=math.min(s.lowestHealth,U.nativeHealth(s.actor))
        local combat=SC.Combat.peek(s.actor) or {}
        local readiness=combat.readiness or {}
        local endurance=num(call(s.actor:getStats(),"get",CharacterStat.ENDURANCE))
        s.lowestEndurance=math.min(s.lowestEndurance,endurance)
        local action=tostring(combat.lastAction or "idle")
        s.actions[action]=(s.actions[action] or 0)+dt
        local retreat=combat.retreating==true
        if retreat then
            s.retreatSeconds=s.retreatSeconds+dt
            if not s.wasRetreating then
                s.retreatEpisodes=s.retreatEpisodes+1;s.retreatStarted=current;s.retreatOrigin=p
            end
            s.maxRetreatEpisodeSeconds=math.max(s.maxRetreatEpisodeSeconds,(current-s.retreatStarted)/1000)
            s.maxRetreatEpisodeDistance=math.max(s.maxRetreatEpisodeDistance,distance(p,s.retreatOrigin))
            local cause=tostring(combat.overrun and combat.overrun.cause or action)
            s.causes[cause]=(s.causes[cause] or 0)+dt
        else
            s.retreatStarted=nil;s.retreatOrigin=nil
        end
        s.wasRetreating=retreat
        if combat.overrun and combat.overrun.overrun then s.overrunSeconds=s.overrunSeconds+dt end
        if action:find("kite",1,true) or action:find("backstep",1,true) or action:find("backpedal",1,true) then
            s.kiteSeconds=s.kiteSeconds+dt
        end
        local back=movingBack(s,current)
        if back==true then
            s.backwardSeconds=s.backwardSeconds+dt
            if call(s.actor,"isPerformingAttackAnimation")==true then s.attackBackwardSeconds=s.attackBackwardSeconds+dt end
        end
        local nearest=math.huge
        for i,r in ipairs(s.zombies) do
            local hp=num(call(r.actor,"getHealth"),r.lastHealth)
            s.loss=s.loss+math.max(0,r.lastHealth-hp);r.lastHealth=hp
            if not r.dead and call(r.actor,"getModData").SC_SoloMelee~=r.token then
                return fail("zombie_identity","receipt changed case=" .. s.case .. " zombie=" .. i
                    .. " actual=" .. tostring(call(r.actor,"getModData").SC_SoloMelee))
            end
            if not r.dead and call(r.actor,"isDead")==true then r.dead=true;s.kills=s.kills+1 end
            if not r.dead then nearest=math.min(nearest,distance(p,point(r.actor))) end
        end
        if distance(p,s.lastPosition)>0.02 then s.stillSince=current end
        if nearest<5 then s.maxStill=math.max(s.maxStill,(current-s.stillSince)/1000) else s.stillSince=current end
        s.lastPosition=p
        local collision=num(call(s.actor,"getCompanionAttackCollisionSerial"))
        if collision~=s.lastCollision then
            s.collisions=s.collisions+collision-s.lastCollision
            if num(call(s.actor,"getCompanionAttackCollisionHitCount"))==0 then s.emptyCollisions=s.emptyCollisions+1 end
            s.lastCollision=collision
        end
        if combat.lastCombatEvidenceAt~=s.lastEvidenceAt then
            s.lastEvidenceAt=combat.lastCombatEvidenceAt
            local e=combat.lastCombatEvidence or {}
            if e.result=="landed" then s.landed=s.landed+1 elseif e.result=="no_effect" then s.noEffect=s.noEffect+1 end
            if e.action=="shove" then s.shoves=s.shoves+1 elseif e.action=="stomp" then s.stomps=s.stomps+1 end
        end
        if alive(s.actor) and call(s.actor,"getPrimaryHandItem")~=s.item then s.unexpectedWeapon=s.unexpectedWeapon+1 end
        s.samples[#s.samples+1]={format((current-s.started)/1000),format(p.x),format(p.y),
            nearest<math.huge and format(nearest) or "",format(U.nativeHealth(s.actor)),
            format(endurance),action,tostring(retreat),
            tostring(combat.overrun and combat.overrun.cause),tostring(back),
            tostring(call(s.actor,"isPerformingAttackAnimation")),s.kills,format(call(s.item,"getCondition")),
            tostring(combat.overrun and combat.overrun.localKiteReason),tostring(readiness.support),
            tostring(readiness.immediate),tostring(readiness.close),tostring(readiness.enduranceReserve),
            tostring(readiness.combatSkill),tostring(readiness.combatSkillName),
            tostring(readiness.weaponCost),tostring(readiness.internalRisk),
            tostring(combat.kiteBurst and combat.kiteBurst.curve==true or false)}
        local outcome
        if not alive(s.actor) then outcome="DEAD"
        elseif s.count==0 and current-s.started>=10000 then outcome="IDLE"
        elseif s.count>0 and s.kills==s.count then outcome="CLEAR"
        elseif Probe.withdrawalComplete((current-(s.retreatStarted or current))/1000,
            s.retreatOrigin and distance(p,s.retreatOrigin) or 0,s.maxDisplacement) then outcome="WITHDREW"
        elseif current-s.started>=Probe.trialTimeoutMs(H.config) then outcome="TIMEOUT" end
        if not outcome then return end
        local medical=SC.Medical.assess(s.actor)
        local row={case=s.case,weapon=s.weapon[2],zombies=s.count,outcome=outcome,kills=s.kills,
            health=format(U.nativeHealth(s.actor)),lowest_health=format(s.lowestHealth),bites=medical.bites or 0,
            seconds=format((current-s.started)/1000),endurance_start=format(s.initialEndurance),
            endurance_end=format(call(s.actor:getStats(),"get",CharacterStat.ENDURANCE)),
            condition_start=s.initialCondition,condition_end=num(call(s.item,"getCondition")),melee_skill=3,maintenance_skill=3,
            native_min_range=format(s.nativeMin),native_max_range=format(s.nativeMax),
            accepted_min_range=format(s.acceptMin),accepted_max_range=format(s.acceptMax),
            native_contacts=s.contacts,accepted_damage_events=s.accepted,health_loss_observed=format(s.loss),
            impacts_backward=s.backwardImpacts,damage_backward=s.backwardDamage,contacts_beyond_native_range=s.outsideNative,
            contacts_beyond_tolerance=s.outsideTolerance,contacts_behind_facing=s.behindFacing,impacts_unknown_motion=s.unknownMotion,
            collision_events=s.collisions,empty_collisions=s.emptyCollisions,evidence_landed=s.landed,evidence_no_effect=s.noEffect,
            shoves=s.shoves,stomps=s.stomps,kite_seconds=format(s.kiteSeconds),backward_seconds=format(s.backwardSeconds),
            attack_backward_seconds=format(s.attackBackwardSeconds),retreat_seconds=format(s.retreatSeconds),retreat_episodes=s.retreatEpisodes,
            overrun_seconds=format(s.overrunSeconds),max_displacement=format(s.maxDisplacement),max_still_seconds=format(s.maxStill),
            minimum_player_distance=format(s.minPlayerDistance),swing_sounds=num(call(s.actor,"getCompanionSwingSounds"))-s.soundStart,
            unexpected_weapon_samples=s.unexpectedWeapon,minimum_hit_distance=s.minHit<math.huge and format(s.minHit) or "",
            maximum_hit_distance=s.contacts>0 and format(s.maxHit) or "",actions=histogram(s.actions),retreat_causes=histogram(s.causes),
            max_retreat_episode_seconds=format(s.maxRetreatEpisodeSeconds),
            max_retreat_episode_distance=format(s.maxRetreatEpisodeDistance),
            lowest_endurance=format(s.lowestEndurance),model_skill=tostring(readiness.combatSkill),
            model_perk=tostring(readiness.combatSkillName),weapon_broken=tostring(num(call(s.item,"getCondition"))<=0),
            final_held_type=U.itemType(call(s.actor,"getPrimaryHandItem")) or "none",
            initial_model_skill=tostring(s.initialModel.combatSkill),initial_model_perk=tostring(s.initialModel.combatSkillName)}
        s.rows[#s.rows+1]=row
        if not writeRows(H) or not writeTrace(s,"samples",
            "seconds,x,y,nearest,health,endurance,action,retreating,overrun_cause,backward,attack_animation,kills,condition,kite_context,support,immediate,close,reserve,model_skill,model_perk,weapon_cost,internal_risk,kite_curve",s.samples)
            or not writeTrace(s,"impacts",
            "seconds,zombie,weapon,melee,distance,facing_dot,moving,backward,zombie_health,event,actor_x,actor_y,zombie_x,zombie_y,action_or_damage,frame_dx,frame_dy,frame_ms,motion_age_ms",s.impacts)
            then return fail("results_write",s.case) end
        result("PASS","melee_trial_recorded","case=" .. s.case .. " weapon=" .. s.weapon[2] .. " zombies=" .. s.count
            .. " outcome=" .. outcome .. " kills=" .. s.kills .. " health=" .. row.health
            .. " retreat_seconds=" .. row.retreat_seconds .. " backward_damage=" .. row.damage_backward)
        photo(H,s.case .. "-" .. s.weapon[2] .. "-" .. s.count .. "z-" .. outcome)
        setPhase("solo_melee_cleanup",current);return
    end
    if H.phase=="solo_melee_cleanup" then
        local okay,why=cleanup(SC,s)
        if not okay then
            if current-H.phaseStartedAt>15000 then return fail("cleanup",why) end
            return
        end
        if #s.selected>0 then
            s.cursor=s.cursor+1;s.index=s.selected[s.cursor] or s.last+1
        else s.index=s.index+1 end
        setPhase("solo_melee_prepare",current)
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCSoloMeleeProbe=Probe
return Probe
