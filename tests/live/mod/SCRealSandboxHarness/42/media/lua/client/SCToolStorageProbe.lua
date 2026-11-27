-- SPDX-License-Identifier: MIT
-- Disposable clone: native crates, real capacity, normal LF walking and Loot.
-- No zombie steering or navigation changes. Only the fixture actor is driven.
local P={}
local PIN={x=6428.5,y=5449.5,z=0}
local START={x=6430.5,y=5450.5,z=0}
local function call(o,m,...)
    if not o then return nil end
    local ok,v=pcall(function(...) return o[m](o,...) end,...)
    if ok then return v end
end
local function num(v) return tonumber(tostring(v)) or 0 end
local function photo(H,name)
    pcall(function() getCore():TakeFullScreenshot(H.config.run_id .. "-tools-" .. name .. ".png") end)
end
function P.step(H,now,check,result,setPhase)
    local SC,U=LivingFellows,LivingFellows.GameplayUtil
    if SC.UI and SC.UI.instance then SC.UI.close() end
    H.toolStorage=H.toolStorage or {index=1}
    local s=H.toolStorage
    local function finish()
        if s.decision then SC.Decision.update=s.decision;s.decision=nil end
        setPhase("finish",now)
    end
    local function fail(name,why)
        result("FAIL","tools_" .. name,tostring(why));photo(H,"failed-" .. name);finish()
    end
    if H.phase=="tool_storage_load" then
        if not s.loadAt then
            local sandbox=SandboxVars.LivingFellows
            for option,key in pairs({EncountersEnabled="productionEncounterEnabled",FirstMeetingEnabled="firstMeetingEnabled",
                HouseholdSpawnsEnabled="factionEnabled",OddballsEnabled="oddballsEnabled",BanditCampsEnabled="banditFactionEnabled"}) do
                if sandbox then sandbox[option]=false end;SC.Config._overrides[key]=false
            end
            for _,a in ipairs(SC.Registry.living()) do SC.Actor.remove(a) end
            SC.BaseLife.reset()
            H.player:teleportTo(PIN.x,PIN.y,0)
            getGameTime():setTimeOfDay(12)
            getCore():setAutoZoom(0,false)
            for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
            s.loadAt=now;return
        end
        if now-s.loadAt<10000 then return end
        local centre=U.gridSquare(math.floor(PIN.x),math.floor(PIN.y),0)
        if not centre then return fail("field_unloaded","centre") end
        H.clearZombiesNear(centre,80)
        local ok,why=SC.BaseLife.create(centre,"Tool storage overflow test")
        if not ok then return fail("camp",why) end
        s.rows={};s.containers={};s.objects={}
        for index=1,3 do
            local sq=U.gridSquare(math.floor(PIN.x)+5,math.floor(PIN.y)-3+(index-1)*3,0)
            if not sq or not U.isSquareFree(sq) or U.squareOccupyingObject(sq) then return fail("crate_site",index) end
            local o=IsoThumpable.new(getCell(),sq,"carpentry_01_16",false,{})
            o:setIsContainer(true);o:setContainer(ItemContainer.new("crate",sq,o))
            o:getContainer():setCapacity(3);o:getContainer():setExplored(true)
            sq:AddSpecialObject(o);sq:RecalcAllWithNeighbours(true)
            local registered,row=SC.BaseLife.registerStorage(o,"tools")
            if not registered then return fail("registration",row) end
            s.rows[index],s.containers[index],s.objects[index]=row,o:getContainer(),o
        end
        local spawnSquare=U.gridSquare(math.floor(START.x),math.floor(START.y),0)
        local spawnWhy
        s.ticket,spawnWhy=SC.Actor.beginSpawn(spawnSquare,{recruited=true,
            background={profession="unemployed",aptitude="fast_learner",abilitySeed="tool-overflow"},
            identity={forename="Tool",surname="Tester",gender="woman",outfit="Generic01",visualSeed=2728}})
        if not s.ticket then return fail("spawn",spawnWhy or "no ticket") end
        setPhase("tool_storage_spawn",now);return
    end
    if H.phase=="tool_storage_spawn" then
        local actor,why=SC.Actor.pollSpawn(s.ticket)
        if not actor then
            if why~="spawn_pending" or now-H.phaseStartedAt>15000 then return fail("spawn",why) end
            return
        end
        s.actor=actor
        local assigned,assignWhy=SC.BaseLife.assign(SC.Registry.idOf(actor),"generalist",true)
        if not assigned then return fail("assignment",assignWhy) end
        local ordered,orderWhy=SC.Commands.issue(SC.Registry.idOf(actor),"stay",nil,H.player)
        if not ordered then return fail("order",orderWhy) end
        s.decision=SC.Decision.update
        SC.Decision.update=function(a,...)
            if a==s.actor then return true,"tool_storage_fixture" end
            return s.decision(a,...)
        end
        setPhase("tool_storage_prepare",now);return
    end
    if H.phase=="tool_storage_prepare" then
        if s.index>3 then
            result("PASS","tools_matrix_complete","three native deposit scenarios plus all-full hold/recovery")
            finish();return
        end
        if s.tool then
            local owner=call(s.tool,"getContainer")
            if owner then owner:Remove(s.tool) end
        end
        s.actor:teleportTo(START.x,START.y,0)
        s.actor:setCurrentSquare(U.gridSquare(math.floor(START.x),math.floor(START.y),0))
        s.actor:setPrimaryHandItem(nil);s.actor:setSecondaryHandItem(nil)
        s.tool=s.actor:getInventory():AddItem("Base.Hammer")
        if not s.tool then return fail("tool","native hammer unavailable") end
        s.nativeId=num(call(s.tool,"getID"))
        s.state={};s.started=now;s.nextAt=0;s.holdProved=false
        for index,container in ipairs(s.containers) do
            local items=U.inventoryItems(container,128)
            for _,item in ipairs(items) do container:Remove(item) end
            if index<=s.index then
                if not container:AddItem("Base.Hammer") or not container:AddItem("Base.Hammer") then
                    return fail("ballast","native filler missing")
                end
                if math.abs(num(container:getCapacityWeight())-num(container:getEffectiveCapacity(s.actor)))>0.001 then
                    return fail("capacity","full crate did not reach native capacity exactly")
                end
                if U.containerHasRoom(container,s.actor,s.tool)~=false then return fail("capacity","full crate admitted hammer") end
            end
        end
        result("PASS","tools_trial_start","filled=" .. s.index .. " tool_id=" .. tostring(s.nativeId)
            .. " first_used=" .. tostring(s.containers[1]:getCapacityWeight())
            .. " capacity=" .. tostring(s.containers[1]:getEffectiveCapacity(s.actor)))
        photo(H,"case-" .. s.index .. "-start")
        setPhase("tool_storage_return",now);return
    end
    if H.phase=="tool_storage_return" then
        if now<s.nextAt then return end;s.nextAt=now+100
        local okay,why,destination,target=SC.BaseWork.returnToStorage(s.actor,s.state,s.rows[1],s.containers[1],s.tool)
        if s.index==3 and not s.holdProved then
            if okay~=false or why~="destination_full" or call(s.tool,"getContainer")~=s.actor:getInventory() then
                return fail("all_full_hold",why)
            end
            result("PASS","tools_all_full_retained","exact native tool stayed with its companion")
            s.holdProved=true
            for _,item in ipairs(U.inventoryItems(s.containers[3],128)) do s.containers[3]:Remove(item) end
            return
        end
        if okay~=true then return fail("return",why) end
        if why=="base_supply_returned" then
            local expected=s.index==1 and 2 or 3
            if num(call(s.tool,"getID"))~=s.nativeId or call(s.tool,"getContainer")~=s.containers[expected]
                or U.inventoryContains(s.containers[expected],s.tool)~=true
                or U.inventoryContains(s.actor:getInventory(),s.tool)==true
                or destination~=s.rows[expected] or target~=s.containers[expected] then
                return fail("identity","wrong tool or destination")
            end
            for index=1,s.index do
                if index~=expected and num(s.containers[index]:getFreeCapacity(s.actor))~=0 then
                    return fail("full_store_changed",index)
                end
            end
            result("PASS","tools_deposit_verified","filled=" .. s.index .. " destination=" .. expected
                .. " tool_id=" .. tostring(s.nativeId) .. " seconds=" .. string.format("%.2f",(now-s.started)/1000)
                .. " target_used=" .. tostring(s.containers[expected]:getCapacityWeight()))
            photo(H,"case-" .. s.index .. "-stored-" .. expected)
            s.index=s.index+1;setPhase("tool_storage_prepare",now);return
        end
        if now-s.started>45000 then return fail("return_timeout",why) end
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCToolStorageProbe=P
return P
