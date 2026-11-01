-- SPDX-License-Identifier: MIT
-- Disposable native compatibility run: retain the indoor primary and the real
-- saved companion; exercise public expedition APIs without changing path results.
local Probe = {}
local function call(object, method, ...)
    if not object then return nil end
    local okay, fn = pcall(function() return object[method] end)
    if not okay or type(fn) ~= "function" then return nil end
    local accepted, value = pcall(fn, object, ...)
    if accepted then return value end
end
local function uiEvidence(actor)
    local count, visible, names = 0, 0, {}
    local list = UIManager and UIManager.UI
    if not list then return "actorPanels=unavailable" end
    local luaList = type(list) == "table"
    local size = luaList and #list or list:size()
    for index = luaList and 1 or 0, luaList and size or size - 1 do
        local element = luaList and list[index] or list:get(index)
        local panel = type(element) == "table" and element or call(element, "getTable")
        if panel and panel.player == actor then
            count = count + 1
            names[#names+1] = tostring(panel.Type or element)
            if call(element, "isVisible") then visible = visible + 1 end
        end
    end
    return "actorPanels=" .. count .. ";visible=" .. visible .. ";panelTypes=" .. table.concat(names,",")
end
local function statusBars(actor)
    local bars, list = {}, UIManager and UIManager.UI
    if not list then return bars end
    local luaList = type(list)=="table"
    local size=luaList and #list or list:size()
    for index=luaList and 1 or 0,luaList and size or size-1 do
        local element=luaList and list[index] or list:get(index)
        local panel=type(element)=="table" and element or call(element,"getTable")
        if panel and panel.Type=="SSBar" and panel.player==actor then bars[#bars+1]=panel end
    end
    return bars
end
local function trace(fixture, label)
    local SC = SurvivorCompanion
    local mission = SC.ExpeditionPrototype.current()
    local scout = mission and mission.scout
    local actor, primary = fixture.leader.actor, fixture.primary
    local nav = SC.Navigation.status(actor) or {}
    local decision = SC.Decision.peek(actor) or {}
    local action = SC.ActionSupervisor.current(actor)
    local waypoint = mission and mission.testWaypoint
    if SCSplitScreenProbe and type(SCSplitScreenProbe.debugPrimaryCutawaySample)=="function" then
        local okay, facts=pcall(SCSplitScreenProbe.debugPrimaryCutawaySample,
            math.floor(primary:getX()),math.floor(primary:getY()),math.floor(primary:getZ()))
        if okay and type(facts)=="string" then
            fixture.lightingCounter=tonumber(string.match(facts,"visibilityNativeCounter0=(%d+)"))
        end
    end
    local line = label .. ";cycle=" .. fixture.cycle .. ";phase=" .. tostring(scout and scout.phase)
        .. ";slot1=" .. tostring(getSpecificPlayer(1)) .. ";playerNum=" .. tostring(call(actor, "getPlayerNum"))
        .. ";leader=" .. tostring(call(actor,"getX")) .. "," .. tostring(call(actor,"getY")) .. "," .. tostring(call(actor,"getZ"))
        .. ";health=" .. tostring(call(call(actor,"getBodyDamage"),"getOverallBodyHealth"))
        .. ";primary=" .. tostring(call(primary,"getX")) .. "," .. tostring(call(primary,"getY"))
        .. ";primaryRoom=" .. tostring(call(call(primary,"getCurrentSquare"),"getRoom"))
        .. ";issue=" .. tostring(mission and mission.technicalIssue and mission.technicalIssue.reason)
        .. ";waypoint=" .. (waypoint and (waypoint.x..":"..waypoint.y..":"..waypoint.z) or "nil")
        .. ";nav="..tostring(nav.phase)..":"..tostring(nav.target)..":"..tostring(nav.lastMovementReason)
        .. ";navFailure="..tostring(nav.terminalReason)..":"..tostring(nav.pathReason)
        .. ";decision="..tostring(decision.current)..":"..tostring(decision.intent)
        .. ";actionOwner="..tostring(action and action.owner)..":"..tostring(action and action.kind)
        .. ";nativeOwner="..tostring(call(actor,"getCompanionMovementOwner"))
        .. ";blocked="..tostring(call(actor,"isBlockMovement"))..";asleep="..tostring(call(actor,"isAsleep"))
        .. ";lightingCounter0=" .. tostring(fixture.lightingCounter) .. ";" .. uiEvidence(actor)
    print("SC_REAL_SANDBOX|EXPEDITION_COMPAT|" .. line)
    local writer = getFileWriter("SurvivorCompanionHarness/expedition-compatibility.log", true, true)
    if writer then writer:writeln(line); writer:close() end
end
local function cleanup(fixture)
    if fixture and fixture.held then
        call(fixture.primary, "setBlockMovement", fixture.previousBlock)
        fixture.held = false
    end
end
function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local fixture = H.expeditionCompatibility
    local function fail(name, detail)
        result("FAIL", name, detail); cleanup(fixture); setPhase("finish", current)
    end
    if H.phase == "expedition_compatibility_setup" then
        if #SC.Registry.records() == 0 and current - H.phaseStartedAt < 15000 then return end
        if not check("expedition_compatibility_fresh_solo", not SC.ExpeditionPrototype.current()
            and not SC.BaseWatch.current() and getSpecificPlayer(1) == nil,
            "do not interrupt existing views") then setPhase("finish", current); return end
        local room = call(call(H.player, "getCurrentSquare"), "getRoom")
        if not check("expedition_compatibility_primary_indoors", room ~= nil,
            "real player stays inside saved house throughout") then setPhase("finish", current); return end
        local leader, distance
        for _, record in ipairs(SC.Registry.records()) do
            local actor = record.actor
            if actor and call(actor,"isDead") == false and call(actor,"getVehicle") == nil
                and call(actor,"getZ") == call(H.player,"getZ") then
                local d = (actor:getX()-H.player:getX())^2 + (actor:getY()-H.player:getY())^2
                if not distance or d < distance then leader, distance = record, d end
            end
        end
        if not check("expedition_compatibility_saved_leader", leader ~= nil and distance < 40^2,
            "nearest living saved companion within40tiles; no actor spawning") then setPhase("finish",current); return end
        fixture = { leader=leader, primary=H.player, x=H.player:getX(), y=H.player:getY(), z=H.player:getZ(),
            cycle=1, pages=0, sites={}, startedAt=current, nextTrace=current, previousBlock=H.player:isBlockMovement() }
        H.expeditionCompatibility = fixture
        H.player:setBlockMovement(true); fixture.held=true
        trace(fixture,"setup")
        setPhase(H.config.expedition_compatibility_scenario == "manual"
            and "expedition_compatibility_dispatch" or "expedition_compatibility_places",current)
        return
    end
    if not fixture then return fail("expedition_compatibility_fixture","missing") end
    if current >= fixture.nextTrace then fixture.nextTrace=current+2000; trace(fixture,H.phase) end
    if getSpecificPlayer(0) ~= fixture.primary
        or fixture.primary:isDead() or math.abs(fixture.primary:getZ()-fixture.z)>0.1
        or call(call(fixture.primary,"getCurrentSquare"),"getRoom")==nil
        -- Native actor collision can nudge an otherwise movement-blocked
        -- bystander. Permit small physical pushes within the house; never
        -- teleport the primary back or allow leaving the indoor fixture.
        or (fixture.primary:getX()-fixture.x)^2+(fixture.primary:getY()-fixture.y)^2 > 2^2 then
        trace(fixture,"primary_invariant_failed")
        return fail("expedition_compatibility_primary_identity","primary moved or changed slot0 identity")
    end
    if fixture.leader.actor:isDead() then return fail("expedition_compatibility_leader_alive","leader died") end
    if current - fixture.startedAt > 540000 then return fail("expedition_compatibility_deadline","540s; no forced rescue") end
    if H.phase == "expedition_compatibility_places" then
        local actor = fixture.leader.actor
        local rows, why, total = SC.ExpeditionPlaces.targetableNearby(math.floor(actor:getX()),math.floor(actor:getY()),200,32,fixture.pages)
        if not rows then return fail("expedition_compatibility_places",tostring(why)) end
        for _, place in ipairs(rows) do
            if place.distance >= 30 and place.distance <= 190 then fixture.sites[#fixture.sites+1]=place end
        end
        fixture.pages=fixture.pages+#rows
        if #rows>0 and fixture.pages<(total or fixture.pages) and fixture.pages<256 then return end
        table.sort(fixture.sites,function(a,b)
            if (a.kind=="store") ~= (b.kind=="store") then return a.kind=="store" end
            return a.distance < b.distance
        end)
        if not check("expedition_compatibility_real_target",#fixture.sites>0,"mapped buildings="..#fixture.sites) then cleanup(fixture);setPhase("finish",current);return end
        setPhase("expedition_compatibility_dispatch",current)
    elseif H.phase == "expedition_compatibility_dispatch" then
        local accepted, reason
        if H.config.expedition_compatibility_scenario == "manual" then
            accepted,reason=SC.ExpeditionPrototype.start({fixture.leader})
        else
            local place=fixture.sites[1]
            accepted,reason=SC.ExpeditionPrototype.startAtPlace({fixture.leader},place.id,"search",{
                travelMode="straight",request={category="food",quantity=8},turnHomeAfterHours=0.25,doctrine="stealth"})
        end
        if not check("expedition_compatibility_dispatch_"..fixture.cycle,accepted==true,tostring(reason)) then cleanup(fixture);setPhase("finish",current);return end
        fixture.dispatchedAt=current; fixture.joined=false
        setPhase("expedition_compatibility_mission",current)
    elseif H.phase == "expedition_compatibility_mission" then
        fixture.joined=fixture.joined or getSpecificPlayer(1)==fixture.leader.actor
        if fixture.joined and not fixture.joinBars then fixture.joinBars=statusBars(fixture.leader.actor) end
        if H.config.expedition_compatibility_scenario=="manual" and current-fixture.dispatchedAt>=5000
            and SC.ExpeditionPrototype.current() then
            local accepted,reason=SC.ExpeditionPrototype.finishAtPlayer(H.player)
            if not check("expedition_compatibility_manual_close_"..fixture.cycle,accepted==true,tostring(reason)) then cleanup(fixture);setPhase("finish",current);return end
        end
        if not SC.ExpeditionPrototype.current() and getSpecificPlayer(1)==nil then
            if not check("expedition_compatibility_join_observed_"..fixture.cycle,fixture.joined,"owned leader was actually slot1") then cleanup(fixture);setPhase("finish",current);return end
            trace(fixture,"returned_solo")
            fixture.soloLightingCounter=fixture.lightingCounter
            pcall(function() getCore():TakeFullScreenshot(tostring(H.config.run_id).."-expedition-compatibility-solo-"..fixture.cycle..".png") end)
            fixture.soloAt=current
            setPhase("expedition_compatibility_solo",current)
        end
    elseif H.phase == "expedition_compatibility_solo" then
        -- Keep the native render and third-party UI loops running after release.
        if current-fixture.soloAt<15000 then return end
        for _, bar in ipairs(fixture.joinBars or {}) do
            if Keyboard then
                call(bar,"handleKey",Keyboard.KEY_BACKSLASH)
                call(bar,"handleKey",Keyboard.KEY_BACKSLASH)
                call(bar,"handleKey",Keyboard.KEY_L)
            end
        end
        local ui=uiEvidence(fixture.leader.actor)
        check("expedition_compatibility_retired_ui_"..fixture.cycle,
            not string.find(ui,"SSBar",1,true) and not string.find(ui,"ISDesignationZonePanel",1,true),
            "after retained hotkey callbacks;"..ui)
        check("expedition_compatibility_solo_survived_"..fixture.cycle,getSpecificPlayer(1)==nil
            and SC.Registry.byId(fixture.leader.id)~=nil
            and SC.Registry.byId(fixture.leader.id).actor==fixture.leader.actor,
            "15s native render/update after release;"..uiEvidence(fixture.leader.actor))
        check("expedition_compatibility_solo_lighting_"..fixture.cycle,
            fixture.soloLightingCounter~=nil and fixture.lightingCounter~=nil
                and fixture.lightingCounter>fixture.soloLightingCounter+5,
            "primary lighting counter="..tostring(fixture.soloLightingCounter).."->"..tostring(fixture.lightingCounter))
        if fixture.cycle >= (tonumber(H.config.expedition_compatibility_cycles) or 2) then
            cleanup(fixture);setPhase("finish",current)
        else fixture.cycle=fixture.cycle+1;fixture.joinBars=nil;setPhase("expedition_compatibility_dispatch",current) end
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCExpeditionCompatibilityProbe = Probe
return Probe
