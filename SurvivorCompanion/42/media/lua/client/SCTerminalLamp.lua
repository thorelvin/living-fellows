-- SPDX-License-Identifier: MIT
-- Open-window sensor/display state. Bootstrap owns damage-event registration;
-- this module never self-registers or schedules background work.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
local Lamp = SC.TerminalLamp or {}
SC.TerminalLamp = Lamp
Lamp.MAX_RATE = 3

local function rateAt(distance)
    if not distance or distance >= 25 then return 0 end
    local t = math.max(0, math.min(1, (25-distance)/22))
    return math.min(Lamp.MAX_RATE, 0.4 + 2.6*t*t)
end
function Lamp.target(threat)
    threat = threat or {}
    return math.max(math.min(0.8, rateAt(threat.distance)), rateAt(threat.closingDistance))
end
function Lamp.advance(state, threat, now)
    local elapsed = math.max(0, math.min(250, now-(state.lastFrame or now)))/1000
    state.lastFrame = now
    local target = Lamp.target(threat)
    if threat and (threat.partial or threat.unknown) then target = math.max(target, state.target or 0) end
    state.target = math.min(Lamp.MAX_RATE, target)
    local change = math.max(-1.5*elapsed, math.min(1.5*elapsed, state.target-(state.rate or 0)))
    state.rate = math.min(Lamp.MAX_RATE, math.max(0, (state.rate or 0)+change))
    local before = math.floor(state.phase or 0)
    state.phase = (state.phase or 0) + state.rate*elapsed
    if not threat or not (threat.partial or threat.unknown) then
        state.distance = threat and threat.distance
    elseif threat.distance then state.distance = threat.distance end
    return state.rate > 0 and math.floor(state.phase) > before
end
function Lamp.health(player)
    local function read(object,method)
        if SC.GameplayUtil then return (SC.GameplayUtil.call(object,method)) end
        if not object or type(object[method])~="function" then return nil end
        local okay,value=pcall(object[method],object) if okay then return value end
    end
    local body = read(player, "getBodyDamage")
    return { health = tonumber(read(body, "getOverallBodyHealth")),
        bites = tonumber(read(body, "getNumPartsBitten")) or 0,
        scratches = tonumber(read(body, "getNumPartsScratched")) or 0,
        knocked = read(player, "isKnockedDown") == true }
end
function Lamp.hit(before, after, damageKind)
    if not before or not after then return false end
    if after.knocked or after.bites > before.bites or after.scratches > before.scratches then return true end
    if damageKind == "WEAPONHIT" or damageKind == "BITE" or damageKind == "SCRATCH" then return true end
    -- Hunger, sickness and carrying too much can reduce health at the keyboard.
    -- A named non-contact cause must not masquerade as an incoming hit.
    local nonContact={HUNGRY=true,STARVATION=true,THIRST=true,HEAVYLOAD=true,INFECTION=true,
        SICK=true,SICKNESS=true,POISON=true,FOODPOISON=true}
    if damageKind and nonContact[damageKind] then return false end
    return before.health and after.health and before.health-after.health >= 0.5 or false
end
function Lamp.mode()
    return SC.UserOptions and SC.UserOptions.get("terminalLamp") or "flash"
end
function Lamp.active(w)
    return w.system and (w.system.locked or w.menuPage=="building_security") and w.state~="closing"
end
function Lamp.watch(w,now)
    local after=Lamp.health(w.player)
    local cause=w.nonContactDamageAt and now-w.nonContactDamageAt<1000 and w.nonContactDamageKind or nil
    local hit=Lamp.hit(w.healthBaseline,after,cause)
    w.healthBaseline=after
    if hit then w:close() return true end
    if Lamp.active(w) and Lamp.mode()~="off" then
        w.lockSensor=w.lockSensor or {}
        local okay,threat=pcall(SC.TerminalWorld.nearestThreat,w.player,w.lockSensor,now)
        w.lockThreat=okay and threat or {unknown=true}
        if okay and threat.distance and threat.distance<=1.5 and SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"lamp",100) end
    end
    return false
end
function Lamp.draw(w,now)
    if not Lamp.active(w) or Lamp.mode()=="off" then return end
    w.lampState=w.lampState or {}
    local pulse=Lamp.advance(w.lampState,w.lockThreat,now)
    local distance=w.lampState.distance
    if pulse then
        if not w.lampExplained then w.lampExplained=true w.lampExplainUntil=now+5000 end
        if distance and distance<=10 then SC.Terminal.playFeedbackSound("LFTerminalLampTick") end
    end
    local alpha=.18
    if w.lampState.rate>0 then
        alpha=Lamp.mode()=="steady" and (.18+.77*math.max(0,1-(distance or 25)/25))
            or ((w.lampState.phase or 0)%1<.5 and .95 or .12)
    end
    local size=math.max(8,math.floor(w.rowHeight*.45+.5))
    local color=w.colors.title
    w:drawRect(w.layout.right-size,w.layout.hintY+(w.rowHeight-size)/2,size,size,alpha,color[2],color[3],color[4])
end
Lamp._hooks=Lamp._hooks or {}
local hooks=Lamp._hooks
local function damaged(actor,kind)
    local w=SC.Terminal and SC.Terminal.window
    if not w or w.closed or w.player~=actor then return end
    if kind=="WEAPONHIT" or kind=="BITE" or kind=="SCRATCH" or kind=="ZOMBIE" then w:close()
    else
        w.nonContactDamageAt=SC.GameplayUtil.nowMs() w.nonContactDamageKind=tostring(kind)
    end
end
function Lamp.install()
    if hooks.installed then return true end
    hooks.event=Events and Events.OnPlayerGetDamage hooks.callback=damaged
    if hooks.event and hooks.event.Add then
        local okay,reason=pcall(hooks.event.Add,hooks.callback)
        if not okay then pcall(hooks.event.Remove,hooks.callback) hooks.event=nil hooks.callback=nil return false,reason end
    end
    hooks.installed=true return true
end
function Lamp.remove()
    if hooks.event and hooks.event.Remove then local okay,reason=pcall(hooks.event.Remove,hooks.callback) if not okay then return false,reason end end
    hooks.event,hooks.callback,hooks.installed=nil,nil,false return true
end
function Lamp.isInstalled() return hooks.installed==true end
return Lamp
