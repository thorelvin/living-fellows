-- SPDX-License-Identifier: MIT
-- A paid, foreground-only boot lease. It never powers the building, a mounted
-- receiver or a background cracker, and it is never restored after reload.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local J={} SC.EmmaJump=J
J.COST=.05
J.SESSION_MS=600000
J.ACTION_TIME=1200
local leases=setmetatable({}, {__mode="k"})
local function U() return SC.ControlUtil end
function J.active(player,object)
    local lease=leases[object]
    if not lease or player and lease.player~=player then return false end
    local now=U().now()
    if now<lease.at or now>=lease.untilAt or U().call(lease.player,"isDead")==true then return false end
    if type(getSpecificPlayer)=="function" and getSpecificPlayer(0)~=lease.player then return false end
    local x,y,z=U().position(object)
    local state=SC.Terminal.peekState(object)
    return U().present(object) and state and state.identity==lease.identity
        and x==lease.x and y==lease.y and z==lease.z and SC.Terminal.near(lease.player,object)
end
function J.power(player,object)
    local lease=leases[object]
    return J.active(player,object) and {source="jump",charge=lease.charge,remainingMs=math.max(0,lease.untilAt-U().now())} or nil
end
function J.eligible(player,object,battery)
    if type(getSpecificPlayer)=="function" and getSpecificPlayer(0)~=player then return false,"Only the primary operator can connect borrowed power." end
    if not SC.Terminal.isComputer(object) or not U().present(object) or not SC.Terminal.near(player,object)
        or U().call(player,"isDead")==true then return false,"Stand beside the computer." end
    if SC.Terminal.normalPowered(object) or J.active(player,object) then return false,"This computer already has power." end
    if SC.GridControl and SC.GridControl.pinned(object) then return false,"The grid controller needs its installed supply." end
    if U().skill(player)<2 or not U().hasTool(player,"Base.Screwdriver") then return false,"Electrical 2 and a screwdriver are required." end
    if not tostring(U().call(battery,"getFullType")):match("^Base%.CarBattery") or not U().owns(player,battery)
        or (tonumber(U().call(battery,"getCondition")) or 0)<=0 then return false,"Choose an intact car battery you are carrying." end
    if (U().charge(battery) or 0)+.000001<J.COST then return false,"The car battery needs at least 5% charge." end
    return true
end
function J.connect(player,object,battery,expectedIdentity)
    local okay,reason=J.eligible(player,object,battery)
    if not okay then return false,reason end
    local state=SC.Terminal.peekState(object)
    if not state or state.identity~=expectedIdentity then return false,"The computer changed during connection." end
    local before=U().charge(battery)
    if not U().setCharge(battery,math.max(0,before-J.COST)) then return false,"Battery transfer could not be verified. Check its charge before trying again." end
    local x,y,z=U().position(object)
    local now=U().now()
    leases[object]={player=player,identity=state.identity,at=now,untilAt=now+J.SESSION_MS,x=x,y=y,z=z,
        charge=math.floor((before-J.COST)*100+.5)}
    local opened,why=SC.Terminal.open(player,object)
    if not opened then leases[object]=nil return false,"Power connected, but the terminal could not open: "..tostring(why) end
    return true,"Borrowed power connected. EMMA only; up to ten minutes or until you close the screen."
end
function J.use(player,object,battery)
    local okay,reason=J.eligible(player,object,battery)
    if not okay then return false,reason end
    local state,failure=SC.Terminal.computerState(player,object)
    if not state then return false,failure end
    local expected=state.identity
    if not SC.TerminalServices then return false,"Computer installation actions are unavailable." end
    return SC.TerminalServices.install(player,object,function() return J.connect(player,object,battery,expected) end,J.ACTION_TIME)
end
function J.context(context,player,object)
    if SC.Terminal.normalPowered(object) or J.active(player,object) or U().skill(player)<2
        or not U().hasTool(player,"Base.Screwdriver") then return false end
    local menu,count
    count=0
    for _,item in ipairs(U().items(player)) do
        if count>=12 then break end
        if tostring(U().call(item,"getFullType")):match("^Base%.CarBattery") then
            count=count+1
            menu=menu or SC.ContextMenu.group(context,"terminal.maintenance",
                SC.GameplayUtil.text("UI_SC_Context_ComputerMaintenance","Computer maintenance"))
            local selected=item
            local okay,reason=J.eligible(player,object,item)
            local label="Jump-start computer - "..tostring(U().call(item,"getDisplayName") or "car battery").." (5% charge)"
            local option=SC.ContextMenu.action(menu,"terminal.jump:"..count,label,player,function(actor)
                local started,why=J.use(actor,object,selected)
                if not started then U().call(actor,"Say",why) end
            end)
            if option and not okay then option.notAvailable=true;SC.ContextMenu.reason(option,reason) end
        end
    end
    return count>0
end
function J.stop(object) leases[object]=nil end
function J.reset() leases=setmetatable({}, {__mode="k"}) end
function J.watch(window,now)
    local lease=leases[window.object]
    if not lease then return false end
    if SC.Terminal.normalPowered(window.object) then J.stop(window.object) return false end
    if now<lease.at or now>=lease.untilAt then
        J.stop(window.object)
        if SC.Terminal.normalPowered(window.object) then return false end
        window:cancelRequest();window:stopBootSound()
        if window.state=="booting" then window.queue,window.typing={},nil else window:flush() end
        window:print("Borrowed power exhausted. This session is closing.","system")
        window.state,window.closeAt="closing",now+1500
        return true
    end
    if not lease.warned and lease.untilAt-now<=120000 then
        lease.warned=true
        if not SC.EmmaCare.quiet(window.session) then window:print("Borrowed power: two minutes remain.","system") end
    end
    return false
end
return J
