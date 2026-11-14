-- SPDX-License-Identifier: MIT
-- A screening matrix, not a victory gate: ten real guns against waves 1..10.
-- Disposable clone only. Fresh actor/supplies for each trial; no mid-fight
-- healing, ammunition injection, zombie steering or scripted damage.
local Probe = {}
local PIN = {x=6444,y=5461,z=0}
local FILE = "SurvivorCompanionHarness/solo-firearms-results.txt"
local GUNS = {
    {"Base.Pistol","M9"}, {"Base.Pistol2","M1911"},
    {"Base.Revolver_Short","M36"}, {"Base.Revolver_Long","Magnum"},
    {"Base.Shotgun","JS2000"}, {"Base.DoubleBarrelShotgun","DoubleBarrel"},
    {"Base.HuntingRifle","MSR700"}, {"Base.VarmintRifle","MSR788"},
    {"Base.AssaultRifle2","M14"}, {"Base.AssaultRifle","M16"},
}
local COLUMNS = {"trial","case","spacing_scale","weapon","zombies","outcome","kills","health","bites",
    "seconds","rounds_used","reload_rounds","shoves","retreat_samples",
    "minimum_player_distance","maximum_displacement","blocked","gun_ammo","jammed","starting_load","carry_capacity",
    "shot_distance_average","shot_distance_minimum","reload_distance_minimum","reposition_samples","gunshot_sounds",
    "service_walk_samples","service_run_samples","walking_reload_rounds","walking_racks",
    "selected_shot_distance_average","live_target_switches","wounded_target_switches",
    "native_gun_hit_events","accepted_damage_events","observed_health_loss","vision_modifier","start_time_of_day",
    "surviving_hit_targets","survivors_wounded","zombie_results"}
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
        getCore():TakeFullScreenshot(H.config.run_id .. "-solo-" .. label .. ".png")
    end)
end
local function writeRows(H)
    local writer=getFileWriter(FILE,true,false)
    if not writer then return false end
    writer:writeln(table.concat(COLUMNS,","))
    for _,row in ipairs(H.solo.rows) do
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
        if not offset then return nil,"no open 24-tile firing/retreat footprint near requested field" end
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
local function loadedAmmo(gun)
    return num(call(gun,"getCurrentAmmoCount"))
        +(call(gun,"haveChamber")==true and call(gun,"isRoundChambered")==true and 1 or 0)
end
local function totalAmmo(s)
    local total=loadedAmmo(s.gun)
    SurvivorCompanion.PersonalItems.walkActorInventory(s.actor,function(item)
        local kind=call(item,"getFullType")
        if item~=s.gun then
            -- getCount is the scripted loot batch (e.g. five 9mm rounds),
            -- not the quantity represented by this individual inventory item.
            if kind==s.ammoType then total=total+1
            elseif s.magType and kind==s.magType then total=total+num(call(item,"getCurrentAmmoCount")) end
        end
    end,{budget=1024})
    return total
end
local function equip(SC,s,H)
    local actor=s.actor
    -- Fixture-only: compare weapons in the same daylight and real clothing.
    -- Random headgear changes native firearm vision penalties and footwear
    -- changes kiting speed. Never alter either during a measured fight.
    getGameTime():setTimeOfDay(12)
    for _,perk in ipairs({"Strength","Fitness"}) do actor:setPerkLevelDebug(Perks[perk],5) end
    actor:setPerkLevelDebug(Perks.Aiming,3)
    actor:setPerkLevelDebug(Perks.Reloading,3)
    actor:getStats():set(CharacterStat.ENDURANCE,1)
    actor:getStats():set(CharacterStat.FATIGUE,0)
    actor:getStats():set(CharacterStat.HUNGER,0.1)
    actor:getStats():set(CharacterStat.THIRST,0.05)
    actor:getStats():set(CharacterStat.PANIC,0)
    local inv=actor:getInventory()
    -- A single gun, fixed clothing and the same backpack/ammunition budget.
    actor:setPrimaryHandItem(nil);actor:setSecondaryHandItem(nil)
    for _,item in ipairs(SC.GameplayUtil.inventoryItems(inv,128)) do
        call(actor,"removeWornItem",item);inv:Remove(item)
    end
    for _,kind in ipairs({"Base.Tshirt_DefaultTEXTURE_TINT","Base.Trousers_Denim","Base.Shoes_TrainerTINT"}) do
        local item=inv:AddItem(kind)
        if not item then return false,"standard clothing missing: " .. kind end
        actor:setWornItem(item:getBodyLocation(),item)
    end
    local bag=inv:AddItem("Base.Bag_Schoolbag")
    if not bag then return false,"standard backpack missing" end
    actor:setWornItem(bag:canBeEquipped(),bag)
    local supplies=bag:getInventory()
    s.gun=inv:AddItem(s.weapon[1])
    if not s.gun or call(s.gun,"isRanged")~=true then return false,"gun missing" end
    local ammoKey=call(call(s.gun,"getAmmoType"),"getItemKey")
    if not ammoKey then return false,"native ammunition item key missing" end
    s.ammoType=tostring(ammoKey)
    s.magType=call(s.gun,"getMagazineType")
    if s.magType and tostring(s.magType)~="" then s.magType=tostring(s.magType) else s.magType=nil end
    local capacity=num(call(s.gun,"getMaxAmmo"))
    if capacity<1 then return false,"invalid native capacity" end
    if s.magType then
        s.gun:setContainsClip(true)
        for _=1,3 do
            local magazine=supplies:AddItem(s.magType)
            if not magazine then return false,"native magazine missing" end
            magazine:setCurrentAmmoCount(capacity)
        end
    end
    for _=1,120-(s.magType and 3*capacity or 0) do
        if not supplies:AddItem(s.ammoType) then return false,"native loose ammunition missing" end
    end
    s.gun:setCurrentAmmoCount(capacity)
    s.gun:setRoundChambered(call(s.gun,"haveChamber")==true)
    s.gun:setJammed(false)
    if H.config.solo_firearms_empty_start=="true" then
        s.gun:setCurrentAmmoCount(0);s.gun:setRoundChambered(false)
        s.gun:setSpentRoundChambered(false)
    end
    actor:setPrimaryHandItem(s.gun)
    if call(s.gun,"isTwoHandWeapon")==true then actor:setSecondaryHandItem(s.gun) end
    local id=SC.Registry.idOf(actor)
    for _,order in ipairs({{"set_combat_doctrine","weapons_free"},{"set_weapon_priority","firearm"},{"fire_at_will"},{"stay"}}) do
        local okay,why=SC.Commands.issue(id,order[1],order[2],s.player)
        if not okay then return false,why end
    end
    return num(call(actor,"getPerkLevel",Perks.Aiming))==3 and num(call(actor,"getPerkLevel",Perks.Reloading))==3,
        "skill verification"
end
local function cleanup(SC,s)
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
local function clearBodies(s)
    local U=SurvivorCompanion.GameplayUtil
    for y=math.floor(s.arena.y)-22,math.floor(s.arena.y)+22 do
        for x=math.floor(s.arena.x)-22,math.floor(s.arena.x)+22 do
            local bodies={}
            U.squareStaticMovingObjects(square(x,y),function(o)
                if U.instanceOf(o,"IsoDeadBody") then bodies[#bodies+1]=o end
            end,16)
            for _,body in ipairs(bodies) do call(body,"removeFromWorld");call(body,"removeFromSquare") end
        end
    end
end
function Probe.step(H,current,check,result,setPhase)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    if SC.UI and SC.UI.instance then call(SC.UI.instance,"setVisible",false) end
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
    H.solo=H.solo or {rows={},index=num(H.config.solo_firearms_start_case,1),last=num(H.config.solo_firearms_end_case,100),
        defaultScale=num(SC.Config.get("combatRangedSpacingScale"),0.7)}
    local s=H.solo
    if H.config.solo_firearms_calibrate=="true" and not s.sequence then
        s.sequence={};s.index=1
        for _,case in ipairs({6,8,10,45}) do for _,scale in ipairs({0.7}) do
            s.sequence[#s.sequence+1]={case=case,scale=scale}
        end end
        s.last=#s.sequence
    end
    local function fail(name,detail)
        photo(H,string.format("%03d-blocked-%s",s.index,name))
        result("FAIL","solo_" .. name,tostring(detail))
        s.failure=current;setPhase("solo_firearms_failed",current)
    end
    if H.phase=="solo_firearms_failed" then
        if current-s.failure>2000 and cleanup(SC,s) then setPhase("finish",current) end
        return
    end
    if H.phase=="solo_firearms_load" then
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
            result("PASS","solo_population_isolated","background LF arrivals disabled; native zombie behaviour unchanged")
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
        result("PASS","solo_site","requested=6444:5461 arena=" .. format(s.arena.x) .. ":" .. format(s.arena.y)
            .. " observer=" .. format(s.observer.x) .. ":" .. format(s.observer.y) .. " aiming=3 reloading=3")
        setPhase("solo_firearms_prepare",current);return
    end
    if H.phase=="solo_firearms_prepare" then
        if s.index>s.last then
            result("PASS","solo_matrix_recorded","trials=" .. #s.rows .. " file=" .. FILE .. " outcomes are measurements, not guaranteed wins")
            setPhase("finish",current);return
        end
        if getSpecificPlayer(1) or SC.BaseWatch.current() then return fail("view_not_released",s.index) end
        SC.BaseLife.reset()
        getGameTime():setTimeOfDay(12)
        H.clearZombiesNear(square(s.arena.x,s.arena.y),150)
        H.clearZombiesNear(H.player,60)
        clearBodies(s)
        s.case=s.sequence and s.sequence[s.index].case or s.index
        s.scale=s.sequence and s.sequence[s.index].scale or s.defaultScale
        SC.Config._overrides.combatRangedSpacingScale=s.scale
        s.weapon=GUNS[math.floor((s.case-1)/10)+1]
        s.count=(s.case-1)%10+1
        -- Releasing a distant watched map can unload the range. Bring the
        -- primary map here and wait for its real squares before asking to spawn.
        H.player:teleportTo(s.arena.x+3,s.arena.y,0)
        setPhase("solo_firearms_spawn",current);return
    end
    if H.phase=="solo_firearms_spawn" then
        local rangeSquare=square(s.arena.x,s.arena.y)
        local indoorSquare=square(s.indoor:getX(),s.indoor:getY())
        if current-H.phaseStartedAt<1500 or not rangeSquare or not indoorSquare then
            if current-H.phaseStartedAt>15000 then return fail("range_load","range/indoor squares not loaded") end
            return
        end
        s.indoor=indoorSquare
        H.player:setCurrentSquare(square(s.arena.x+3,s.arena.y))
        H.clearZombiesNear(rangeSquare,150)
        local ticket,why=SC.Actor.beginSpawn(square(s.arena.x,s.arena.y),{recruited=true,
            background={profession="unemployed",aptitude="fast_learner",abilitySeed="solo-firearms-aim3"},
            state={personality={version=2,courage=60,caution=50,compassion=50,practicality=50}},
            identity={forename="Range",surname=s.weapon[2],gender="woman",outfit="Generic01",visualSeed=2719}})
        s.ticket=ticket
        if not s.ticket then return fail("actor_spawn",why) end
        setPhase("solo_firearms_poll",current);return
    end
    if H.phase=="solo_firearms_poll" then
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
        okay,why=SC.BaseLife.create(s.indoor,"Solo firearms test camp")
        if not okay then return fail("camp",why) end
        SC.BaseLife.beginZone("area",{x=math.floor(s.arena.x)-8,y=math.floor(s.arena.y)-8,z=0})
        okay,why=SC.BaseLife.finishZone({x=math.floor(s.arena.x)+8,y=math.floor(s.arena.y)+8,z=0},"Firing area")
        if not okay then return fail("camp_area",why) end
        SC.BaseLife.assign(SC.Registry.idOf(actor),"guard",true)
        -- Camera-only staging. Preserve the native Stay anchor at the range;
        -- Base Watch's duty precondition is satisfied in this synchronous call.
        local commands=SC.Commands.peek(actor)
        local previous=commands.order;commands.order="base_duty"
        local called,started,watchWhy=pcall(SC.BaseWatch.start,SC.Registry.idOf(actor))
        commands.order=previous
        if not called or not started then return fail("base_watch",watchWhy or started) end
        setPhase("solo_firearms_join",current);return
    end
    if H.phase=="solo_firearms_join" then
        if getSpecificPlayer(1)~=s.actor then
            if current-H.phaseStartedAt>15000 then return fail("base_watch_join","native slot 1 not ready") end
            return
        end
        s.actor:teleportTo(s.arena.x,s.arena.y,0)
        s.actor:setCurrentSquare(square(s.arena.x,s.arena.y))
        H.player:teleportTo(s.observer.x,s.observer.y,0)
        H.player:setCurrentSquare(square(s.observer.x,s.observer.y))
        s.readyAt=current+1500
        setPhase("solo_firearms_ready",current);return
    end
    if H.phase=="solo_firearms_ready" then
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
        s.started=current;s.nextSample=0;s.zombies={};s.kills=0;s.lowestHealth=100
        s.minimumPlayerDistance=math.huge;s.maximumDisplacement=0;s.reloadRounds=0;s.retreatSamples=0
        s.shoves=0;s.lastEvidenceAt=nil;s.blocked=false;s.lastProgress=current
        s.shotDistanceSum=0;s.shotSamples=0;s.shotDistanceMin=math.huge
        s.selectedDistanceSum=0;s.selectedSamples=0;s.previousTarget=nil;s.liveTargetSwitches=0
        s.woundedTargetSwitches=0;s.gunHitEvents=0;s.acceptedDamageEvents=0;s.observedHealthLoss=0
        s.reloadDistanceMin=math.huge;s.repositionSamples=0
        s.serviceWalkSamples=0;s.serviceRunSamples=0;s.walkingReloadRounds=0;s.walkingRacks=0
        s.walkedActions={};s.previousAction=nil;s.previousPosition=point(s.actor)
        s.previousChamber=call(s.gun,"isRoundChambered");s.previousJam=call(s.gun,"isJammed")
        s.soundStart=num(call(s.actor,"getCompanionGunshotSounds"));s.shotTraces=0
        s.initialAmmo=totalAmmo(s);s.previousLoaded=loadedAmmo(s.gun);s.previousAmmo=s.initialAmmo
        s.startingLoad,s.carryCapacity=U.carryLoad(s.actor)
        if s.startingLoad>s.carryCapacity then return fail("carrying_weight",format(s.startingLoad) .. "/" .. format(s.carryCapacity)) end
        s.deathObserver=function(zombie)
            for _,r in ipairs(s.zombies) do if r.actor==zombie and not r.dead
                and call(zombie,"getModData").SC_SoloFirearms==r.token then r.dead=true;s.kills=s.kills+1;s.lastProgress=U.nowMs() end end
        end
        Events.OnZombieDead.Add(s.deathObserver)
        -- Observe vanilla hit callbacks; never wrap the hit or change damage.
        s.hitObserver=function(zombie,attacker,part,weapon)
            if attacker~=s.actor or weapon~=s.gun or call(attacker,"isShoving")==true
                or call(attacker,"isShoveStompAnim")==true then return end
            for _,r in ipairs(s.zombies) do if r.actor==zombie then
                r.hits=r.hits+1;r.beforeHitHealth=num(call(zombie,"getHealth"),r.initialHealth)
                s.gunHitEvents=s.gunHitEvents+1;return
            end end
        end
        Events.OnHitZombie.Add(s.hitObserver)
        -- Vanilla emits this after Hit() only when isIgnoreDamage is false.
        -- It is a separate observation: not every hit callback damages health,
        -- and the native range-falloff/shotgun path may omit this XP event.
        s.damageObserver=function(attacker,weapon,zombie,damage)
            if attacker~=s.actor or weapon~=s.gun or num(damage)<=0 then return end
            for _,r in ipairs(s.zombies) do if r.actor==zombie then
                r.accepted=r.accepted+1;s.acceptedDamageEvents=s.acceptedDamageEvents+1
                if r.beforeHitHealth~=nil then
                    local loss=math.max(0,r.beforeHitHealth-num(call(zombie,"getHealth"),r.beforeHitHealth))
                    r.loss=r.loss+loss;s.observedHealthLoss=s.observedHealthLoss+loss
                    r.beforeHitHealth=nil
                end
                return
            end end
        end
        Events.OnWeaponHitXp.Add(s.damageObserver)
        for i=1,s.count do
            local depth,lateral=12+math.floor((i-1)/5)*2,(i-1)%5-2
            local x=s.arena.x+s.direction[1]*depth-s.direction[2]*lateral
            local y=s.arena.y+s.direction[2]*depth+s.direction[1]*lateral
            local list=addZombiesInOutfit(math.floor(x),math.floor(y),0,1,nil,0)
            local zombie=call(list,"get",0)
            if not zombie then return fail("zombie_spawn",i) end
            local token={};zombie:getModData().SC_SoloFirearms=token
            s.zombies[#s.zombies+1]={actor=zombie,token=token,dead=false,hits=0,accepted=0,loss=0,
                initialHealth=num(call(zombie,"getHealth"),1)}
            zombie:spotted(s.actor,true)
        end
        result("PASS","solo_trial_start","trial=" .. s.index .. " case=" .. s.case .. " scale=" .. s.scale .. " weapon=" .. s.weapon[2] .. " zombies=" .. s.count
            .. " ammo=" .. s.initialAmmo .. " load=" .. format(s.startingLoad) .. "/" .. format(s.carryCapacity)
            .. " vision=" .. format(s.visionModifier) .. " hour=" .. format(s.startTimeOfDay)
            .. " native_view=1 observer_distance=" .. format(distance(point(s.actor),point(H.player))))
        if s.sequence or s.count==1 then photo(H,string.format("%03d-%s-setup",s.index,s.weapon[2])) end
        setPhase("solo_firearms_fight",current);return
    end
    if H.phase=="solo_firearms_fight" then
        if current<s.nextSample then return end
        s.nextSample=current+100
        if not alive(H.player) or getSpecificPlayer(0)~=H.player then return fail("observer_alive","trial invalid") end
        local separation=distance(point(s.actor),point(H.player))
        s.minimumPlayerDistance=math.min(s.minimumPlayerDistance,separation)
        if separation<10 then return fail("observer_clearance","fighter reached observer") end
        s.maximumDisplacement=math.max(s.maximumDisplacement,distance(point(s.actor),s.arena))
        s.lowestHealth=math.min(s.lowestHealth,U.nativeHealth(s.actor))
        local combat=SC.Combat.peek(s.actor)
        local selected=combat and combat.target
        if selected and selected~=s.previousTarget then
            if s.previousTarget then
                for _,r in ipairs(s.zombies) do if r.actor==s.previousTarget then
                    local health=num(call(r.actor,"getHealth"),r.initialHealth)
                    if not r.dead and call(r.actor,"isDead")==false then
                        s.liveTargetSwitches=s.liveTargetSwitches+1
                        if health>0 and health<r.initialHealth-0.01 then
                            s.woundedTargetSwitches=s.woundedTargetSwitches+1
                        end
                    end
                    break
                end end
            end
            s.previousTarget=selected
        end
        local nearest=math.huge
        for _,r in ipairs(s.zombies) do if not r.dead and call(r.actor,"isDead")==false then
            nearest=math.min(nearest,distance(point(s.actor),point(r.actor)))
        end end
        local loaded=loadedAmmo(s.gun)
        -- Death can move the inventory to its corpse before this observer runs.
        -- Keep the last living sample rather than count that move as gunfire.
        local ammo=alive(s.actor) and totalAmmo(s) or s.previousAmmo
        if alive(s.actor) and nearest<math.huge then
            if s.previousAmmo-ammo==1 and s.previousLoaded-loaded==1 then
                s.shotDistanceSum=s.shotDistanceSum+nearest;s.shotSamples=s.shotSamples+1
                s.shotDistanceMin=math.min(s.shotDistanceMin,nearest)
                if selected then
                    s.selectedDistanceSum=s.selectedDistanceSum+distance(point(s.actor),point(selected))
                    s.selectedSamples=s.selectedSamples+1
                end
                if s.shotTraces<3 then
                    s.shotTraces=s.shotTraces+1
                    result("PASS","solo_shot_geometry","case=" .. s.case .. " distance=" .. format(nearest)
                        .. " " .. tostring(call(s.actor,"getCompanionRangedReadiness")))
                    result("PASS","solo_shot_steadiness","case=" .. s.case
                        .. " delay=" .. tostring(call(s.actor,"getAimingDelay"))
                        .. " panic=" .. tostring(call(s.actor:getStats(),"get",CharacterStat.PANIC))
                        .. " recoil=" .. tostring(call(s.actor,"getRecoilDelay")))
                end
            end
            local queue=ISTimedActionQueue.getTimedActionQueue(s.actor)
            local action=queue and queue.current
            if action and action.gun==s.gun then s.reloadDistanceMin=math.min(s.reloadDistanceMin,nearest) end
            local p=point(s.actor)
            if action and action.gun==s.gun and distance(p,s.previousPosition)>0.001
                and call(s.actor,"isMoving")==true then
                if call(s.actor,"isRunning")==true or call(s.actor,"isSprinting")==true then
                    s.serviceRunSamples=s.serviceRunSamples+1
                else
                    s.serviceWalkSamples=s.serviceWalkSamples+1;s.walkedActions[action]=true
                    if s.serviceWalkSamples==1 then
                        result("PASS","solo_gun_service_walk","case=" .. s.case
                            .. " native_action=" .. tostring(action.Type) .. " running=false"
                            .. " nearest=" .. format(nearest))
                        photo(H,string.format("%03d-%s-walking-service",s.index,s.weapon[2]))
                    end
                end
            end
            local walking=s.walkedActions[action] or s.walkedActions[s.previousAction]
            if walking and loaded>s.previousLoaded then
                s.walkingReloadRounds=s.walkingReloadRounds+loaded-s.previousLoaded
            end
            if s.previousAction and s.previousAction.Type=="ISRackFirearm"
                and s.walkedActions[s.previousAction]
                and ((s.previousChamber~=true and call(s.gun,"isRoundChambered")==true)
                    or (s.previousJam==true and call(s.gun,"isJammed")==false)) then
                s.walkingRacks=s.walkingRacks+1
            end
            s.previousAction=action;s.previousPosition=p
            s.previousChamber=call(s.gun,"isRoundChambered");s.previousJam=call(s.gun,"isJammed")
        end
        if combat and combat.rangedReposition and combat.lastAction=="backstep" then
            s.repositionSamples=s.repositionSamples+1
        end
        if loaded>s.previousLoaded then s.reloadRounds=s.reloadRounds+loaded-s.previousLoaded end
        if ammo<s.previousAmmo then s.lastProgress=current end
        s.previousLoaded,s.previousAmmo=loaded,ammo
        if combat and combat.lastCombatEvidenceAt~=s.lastEvidenceAt then
            s.lastEvidenceAt=combat.lastCombatEvidenceAt
            local e=combat.lastCombatEvidence
            if e and e.action=="shove" then s.shoves=s.shoves+1 end
        end
        if combat and combat.retreating==true then s.retreatSamples=s.retreatSamples+1 end
        for _,r in ipairs(s.zombies) do
            if not r.dead and call(r.actor,"getModData").SC_SoloFirearms~=r.token then return fail("zombie_identity","receipt changed") end
            if not r.dead and call(r.actor,"isDead")==true then r.dead=true;s.kills=s.kills+1 end
        end
        if (current-s.lastProgress>15000 or s.lowestHealth<85) and not s.blocked then
            s.blocked=true;photo(H,string.format("%03d-%s-%dz-blocked",s.index,s.weapon[2],s.count))
            result("PASS","solo_block_snapshot","case=" .. s.index .. " native_state=" .. tostring(call(s.actor,"getCompanionActionStateName"))
                .. " ammo=" .. loaded .. " reserve_total=" .. ammo .. " jammed=" .. tostring(call(s.gun,"isJammed"))
                .. " combat_action=" .. tostring(combat and combat.lastAction)
                .. " hp=" .. format(U.nativeHealth(s.actor)))
            local queue=ISTimedActionQueue.getTimedActionQueue(s.actor)
            local active=queue and queue.current
            local key=call(call(s.gun,"getAmmoType"),"getItemKey")
            local inv=s.actor:getInventory()
            result("PASS","solo_reload_state","case=" .. s.case
                .. " root=" .. tostring(call(inv,"getItemCount",key))
                .. " recursive=" .. tostring(call(inv,"getItemCountRecurse",key))
                .. " queue=" .. tostring(queue and queue.queue and #queue.queue)
                .. " current=" .. tostring(active and active.Type)
                .. " bullets=" .. tostring(active and call(active.bullets,"size"))
                .. " isLoading=" .. tostring(call(s.actor,"getVariableBoolean","isLoading"))
                .. " reloadType=" .. tostring(call(s.actor,"getVariableString","WeaponReloadType"))
                .. " moving=" .. tostring(call(s.actor,"isMoving")) .. " running=" .. tostring(call(s.actor,"isRunning"))
                .. " rejected=" .. tostring(combat and combat.lastRejectedReason))
            local nativeActions=call(s.actor,"getCharacterActions")
            result("PASS","solo_reload_native","primary=" .. tostring(call(s.actor,"getPrimaryHandItem")==s.gun)
                .. " started=" .. tostring(active and call(active,"isStarted"))
                .. " head=" .. tostring(active and call(nativeActions,"get",0)==active.action)
                .. " count=" .. tostring(call(nativeActions,"size"))
                .. " time=" .. tostring(active and call(active.action,"getCurrentTime"))
                .. " attackStarted=" .. tostring(call(s.actor,"isAttackStarted"))
                .. " attackAnim=" .. tostring(call(s.actor,"isPerformingAttackAnimation"))
                .. " aiming=" .. tostring(call(s.actor,"isAiming")))
            result("PASS","solo_reload_animation","performing=" .. tostring(call(s.actor,"getVariableString","PerformingAction"))
                .. " action=" .. tostring(call(s.actor,"getVariableBoolean","IsPerformingAnAction"))
                .. " attacking=" .. tostring(call(s.actor,"isAttacking"))
                .. " turning=" .. tostring(call(s.actor,"isTurning"))
                .. " racking=" .. tostring(call(s.actor,"getVariableBoolean","isRacking"))
                .. " unloading=" .. tostring(call(s.actor,"getVariableBoolean","isUnloading"))
                .. " clips=" .. tostring(call(s.actor,"getCompanionActiveAnimationNames")))
            if combat and combat.rangedBand then
                result("PASS","solo_spacing_state","nearest=" .. format(nearest)
                    .. " firing=" .. format(combat.rangedBand.firing)
                    .. " reload=" .. format(combat.rangedBand.reload)
                    .. " desired=" .. format(combat.rangedBand.reloadResume)
                    .. " movingFor=" .. tostring(combat.rangedReposition
                        and current-(combat.rangedReposition.startedAt or current)))
            end
            for i=1,math.min(queue and queue.queue and #queue.queue or 0,8) do
                local action=queue.queue[i]
                result("PASS","solo_reload_queue","index=" .. i .. " type=" .. tostring(action.Type)
                    .. " exactGun=" .. tostring(action.gun==s.gun) .. " exactActor=" .. tostring(action.character==s.actor))
            end
            for i,r in ipairs(s.zombies) do if not r.dead then
                local p=point(r.actor)
                result("PASS","solo_block_target","case=" .. s.index .. " zombie=" .. i .. " x=" .. format(p.x)
                    .. " y=" .. format(p.y) .. " hp=" .. format(call(r.actor,"getHealth"))
                    .. " target=" .. (call(r.actor,"getTarget")==s.actor and "fighter" or "other")
                    .. " native_state=" .. tostring(call(r.actor,"getCurrentStateName")))
            end end
        end
        local outcome
        if not alive(s.actor) then outcome="DEAD"
        elseif s.kills==s.count then outcome="WIN"
        elseif s.maximumDisplacement>26 and s.retreatSamples>10 then outcome="WITHDREW"
        elseif current-s.started>90000 then outcome="TIMEOUT" end
        if not outcome then return end
        local survivingHits,wounded,distribution=0,0,{}
        for i,r in ipairs(s.zombies) do
            local health=num(call(r.actor,"getHealth"),r.initialHealth)
            if not r.dead and health>0 then
                if r.hits>0 then survivingHits=survivingHits+1 end
                if health<r.initialHealth-0.01 then wounded=wounded+1 end
            end
            distribution[#distribution+1]=i .. ":hits=" .. r.hits .. ":accepted="
                .. r.accepted .. ":loss=" .. format(r.loss) .. ":dead="
                .. tostring(r.dead or call(r.actor,"isDead")==true) .. ":hp="
                .. format(health) .. "/" .. format(r.initialHealth)
        end
        local assessment=SC.Medical.assess(s.actor)
        local row={trial=s.index,case=s.case,spacing_scale=s.scale,weapon=s.weapon[2],zombies=s.count,outcome=outcome,kills=s.kills,
            health=format(U.nativeHealth(s.actor)),bites=assessment.bites or 0,seconds=format((current-s.started)/1000),
            rounds_used=math.max(0,s.initialAmmo-ammo),reload_rounds=s.reloadRounds,
            shoves=s.shoves,retreat_samples=s.retreatSamples,minimum_player_distance=format(s.minimumPlayerDistance),
            maximum_displacement=format(s.maximumDisplacement),blocked=tostring(s.blocked),gun_ammo=loaded,jammed=tostring(call(s.gun,"isJammed")),
            starting_load=format(s.startingLoad),carry_capacity=format(s.carryCapacity),
            shot_distance_average=s.shotSamples>0 and format(s.shotDistanceSum/s.shotSamples) or "",
            shot_distance_minimum=s.shotDistanceMin<math.huge and format(s.shotDistanceMin) or "",
            reload_distance_minimum=s.reloadDistanceMin<math.huge and format(s.reloadDistanceMin) or "",
            reposition_samples=s.repositionSamples,
            gunshot_sounds=num(call(s.actor,"getCompanionGunshotSounds"))-s.soundStart,
            service_walk_samples=s.serviceWalkSamples,service_run_samples=s.serviceRunSamples,
            walking_reload_rounds=s.walkingReloadRounds,walking_racks=s.walkingRacks,
            selected_shot_distance_average=s.selectedSamples>0 and format(s.selectedDistanceSum/s.selectedSamples) or "",
            live_target_switches=s.liveTargetSwitches,wounded_target_switches=s.woundedTargetSwitches,
            native_gun_hit_events=s.gunHitEvents,accepted_damage_events=s.acceptedDamageEvents,
            observed_health_loss=format(s.observedHealthLoss),surviving_hit_targets=survivingHits,
            vision_modifier=format(s.visionModifier),start_time_of_day=format(s.startTimeOfDay),
            survivors_wounded=wounded,zombie_results=table.concat(distribution,"|")}
        s.rows[#s.rows+1]=row
        result("PASS","solo_trial_recorded","trial=" .. s.index .. " case=" .. s.case .. " scale=" .. s.scale .. " weapon=" .. s.weapon[2] .. " zombies=" .. s.count
            .. " outcome=" .. outcome .. " kills=" .. s.kills .. " health=" .. row.health .. " seconds=" .. row.seconds .. " rounds=" .. row.rounds_used)
        if not writeRows(H) then return fail("results_write",FILE) end
        if outcome~="WIN" or s.count==10 then photo(H,string.format("%03d-%s-%dz-%s",s.index,s.weapon[2],s.count,outcome)) end
        setPhase("solo_firearms_cleanup",current);return
    end
    if H.phase=="solo_firearms_cleanup" then
        local okay,why=cleanup(SC,s)
        if not okay then
            if current-H.phaseStartedAt>15000 then return fail("cleanup",why) end
            return
        end
        s.index=s.index+1
        setPhase("solo_firearms_prepare",current)
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCSoloFirearmsProbe=Probe
return Probe
