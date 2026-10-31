-- SPDX-License-Identifier: MIT
-- Bounded leases on the vanilla grid. No square discovery or appliance polling.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.GridControl = SC.GridControl or {}
local G = SC.GridControl
G.KEY, G.CONNECT_KEY, G.CRACK_KEY = "LF_GridControl", "LF_GridConnect", "LF_GridCrack"
G.AREA_RADIUS, G.MAX_LINKS = 40, 5
G.SITES = {
    {id="muldraugh",label="Muldraugh",x=10384,y=10096},
    {id="louisville_south",label="Louisville South",x=14776,y=4080},
    {id="louisville",label="Louisville",x=12104,y=1752},
    {id="riverside_south",label="South of Riverside",x=6768,y=6840},
    {id="rosewood_sw",label="Southwest of Rosewood",x=7184,y=12536},
    {id="far_west",label="Far West steel works",x=1888,y=10880},
    {id="irvington",label="Irvington",x=2192,y=13888},
}
local fallback, cached, lastReconcile = {}, nil, nil
local known=setmetatable({}, {__mode="v"})
local notices, serial = {}, 0
local byId = {}
for _,site in ipairs(G.SITES) do byId[site.id]=site end
local function U() return SC.ControlUtil end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function number(v,lo,hi) return finite(v) and v>=lo and v<=hi end
local function clock() return U() and U().hours() end
local function age()
    local world=type(getWorld)=="function" and getWorld()
    return U() and tonumber(U().call(world,"getWorldAgeDays"))
end
local function options() return type(getSandboxOptions)=="function" and getSandboxOptions() end
local function shut() return U() and tonumber(U().call(options(),"getElecShutModifier")) end
local function validJob(job)
    return type(job)=="table" and byId[job.site] and type(job.controller)=="string"
        and #job.controller<=96 and (job.requiredHours==72 or job.requiredHours==96 or job.requiredHours==120)
        and number(job.doneHours,0,job.requiredHours) and number(job.lastHours,0,1e12)
        and type(job.powered)=="boolean" and type(job.notified)=="table"
        and number(job.x,0,30000) and number(job.y,0,30000) and number(job.z,-32,32)
end
local function validConnection(job)
    return type(job)=="table" and byId[job.site] and type(job.controller)=="string" and #job.controller<=96
        and number(job.doneHours,0,0.5) and number(job.lastHours,0,1e12) and type(job.powered)=="boolean"
        and number(job.radioId,-2147483648,2147483647)
        and number(job.x,0,30000) and number(job.y,0,30000) and number(job.z,-32,32)
end
local function supported()
    return not (type(isClient)=="function" and isClient())
        and not (type(isServer)=="function" and isServer())
end
local function validate(s)
    if type(s)~="table" or s.schema~=1 or not number(s.originalShut,-1,2147483647)
        or s.originalShut~=math.floor(s.originalShut) or type(s.on)~="boolean"
        or not number(s.heat,0,100) or not number(s.heatHours,0,1e12)
        or s.windowHours~=24 and s.windowHours~=48 or type(s.lockedUntilCold)~="boolean"
        or type(s.sites)~="table" or type(s.jobs)~="table" or type(s.connections)~="table"
        or type(s.marked)~="table" or type(s.warned)~="table"
        or s.written~=nil and (not number(s.written,-1,2147483647) or s.written~=math.floor(s.written))
        or s.writeIntent~=nil and (not number(s.writeIntent,-1,2147483647) or s.writeIntent~=math.floor(s.writeIntent))
        or s.standDown~=nil and type(s.standDown)~="string" then return false end
    local count=0
    for id,row in pairs(s.sites) do
        count=count+1
        if count>G.MAX_LINKS or not byId[id] or type(row)~="table"
            or not number(row.linkedAt,0,1e12) or type(row.online)~="boolean"
            or type(row.announced)~="boolean" or type(row.controller)~="string"
            or #row.controller>96 or not number(row.radioId,-2147483648,2147483647) then return false end
    end
    for id,job in pairs(s.connections) do
        count=count+1
        if count>G.MAX_LINKS or not validConnection(job) or job.site~=id or s.sites[id] then return false end
    end
    count=0
    for id,job in pairs(s.jobs) do
        count=count+1
        if count>16 or not validJob(job) or id~=job.controller or not s.sites[job.site] then return false end
    end
    return not s.on or s.written~=nil
end
local function store()
    if cached then return validate(cached) and cached or nil end
    local s=ModData and ModData.getOrCreate and ModData.getOrCreate(G.KEY) or fallback
    if type(s)~="table" then return nil end
    local empty=true
    for _ in pairs(s) do empty=false break end
    if empty then
        local original,hours=shut(),clock()
        if not number(original,-1,2147483647) or not number(hours,0,1e12) then return nil end
        s.schema,s.originalShut,s.on,s.heat,s.heatHours=1,original,false,0,hours
        s.windowHours,s.lockedUntilCold,s.sites,s.marked,s.warned,s.jobs,s.connections=24,false,{},{},{},{},{}
    end
    cached=s
    return validate(s) and s or nil
end
function G.visible()
    if not supported() then return false end
    local s=store()
    return s~=nil and s.originalShut<100000
end
function G.siteFor(object)
    local square=U() and U().square(object)
    local x,y=U() and U().call(square,"getX"),U() and U().call(square,"getY")
    if not finite(x) or not finite(y) then return nil end
    for _,site in ipairs(G.SITES) do
        if (x-site.x)^2+(y-site.y)^2<=G.AREA_RADIUS^2 then return site end
    end
end
local function portable(object)
    local md=U() and U().data(object)
    return type(md)=="table" and type(md.movableData)=="table" and md.movableData or nil
end
local function identity(object)
    local p=portable(object)
    local os=p and p.LF_LarchOS
    return type(os)=="table" and type(os.identity)=="string" and os.identity or nil
end
local function unlocked(object)
    local p=portable(object)
    local saved=p and p.LF_LarchOS
    local os=SC.TerminalSystem and SC.TerminalSystem.normalize(saved)
    return os and os.locked~=true
end
local function hardware(object) return SC.TerminalHardware and SC.TerminalHardware.state(object,false) end
local function radio(state)
    return state and type(state.radio)=="table" and finite(state.radio.id)
end
local function counts(s)
    local linked,online=0,0
    for _,row in pairs(s.sites) do linked=linked+1 if row.online then online=online+1 end end
    return linked,online
end
local function cooldown(s)
    local _,online=counts(s)
    return math.max(3,7-math.max(0,online-1))
end
local function notice(text)
    serial=serial+1
    notices[#notices+1]={id=serial,text=text}
    if #notices>16 then table.remove(notices,1) end
end
function G.notices(after)
    local result={}
    for _,row in ipairs(notices) do if row.id>(after or 0) then result[#result+1]=row end end
    return result,serial
end
local function write(s,value)
    local opt=options()
    if not opt then return false end
    -- Journal before the native write, so recovery needs proof of our exact value.
    s.writeIntent=value
    local okay=pcall(function() opt:set("ElecShutModifier",value) opt:toLua() end)
    if not okay or shut()~=value then
        s.standDown="The grid setting could not be verified."
        return false
    end
    s.written=value s.writeIntent=nil
    return true
end
local function reconcile(s)
    local value=shut()
    local expected=s.on and s.written or s.originalShut
    if value==expected then s.standDown=nil s.writeIntent=nil return true end
    if s.on and value==s.originalShut then
        -- The native lease is already gone (for example, mismatched save
        -- files after interruption). Accept off; never force power back on.
        s.on=false s.written=nil s.writeIntent=nil s.standDown=nil
        notice("The restored grid lease has ended. Power is off; cooling continues.")
        return true
    end
    if not s.on and s.writeIntent~=nil and value==s.writeIntent then
        -- A paired-save interruption, not an arbitrary nearby foreign value.
        if write(s,s.originalShut) then s.standDown=nil return true end
    end
    s.standDown="Another program is managing the grid. I will stay out of it."
    return false
end
local function cutOwned(s,reason)
    if not reconcile(s) or not write(s,s.originalShut) then return false,s.standDown end
    s.on=false s.written=nil
    if reason then notice(reason) end
    return true,"Grid power switched off. Cooling continues."
end
local function advance(s,hours)
    if not number(hours,0,1e12) then return end
    local delta=math.max(0,hours-s.heatHours)
    if hours<s.heatHours then return end
    s.heatHours=hours
    if s.on then
        local rate=95/s.windowHours
        local untilTrip=(100-s.heat)/rate
        if delta>=untilTrip then
            s.heat=100 s.lockedUntilCold=true
            if cutOwned(s,"The grid breaker tripped. It must cool completely before restart.") then
                s.heat=math.max(0,100-(delta-untilTrip)*100/(cooldown(s)*24))
            end
        else s.heat=math.min(100,s.heat+delta*rate) end
        for _,threshold in ipairs({75,90}) do
            if s.on and s.heat>=threshold and not s.warned[threshold] then
                s.warned[threshold]=true
                notice("Grid heat "..threshold.."%. Switch off early to shorten the cooling wait.")
            end
        end
    else s.heat=math.max(0,s.heat-delta*100/(cooldown(s)*24)) end
    if s.heat<=0.0000001 then s.heat=0 s.lockedUntilCold=false end
end
function G.pulse()
    -- The only idle work is the energized breaker's constant-time timer.
    -- Cold worlds and controller cracks do not even read a clock here.
    if not cached or cached.on~=true or not supported() or not validate(cached) then return end
    local s=cached
    local now=U().now()
    if not lastReconcile or now<lastReconcile or now-lastReconcile>=60000 then
        reconcile(s) lastReconcile=now
    end
    if not s.standDown then advance(s,clock()) else s.heatHours=clock() or s.heatHours end
end
function G.restore()
    local s=ModData and ModData.get and ModData.get(G.KEY)
    cached=type(s)=="table" and s or nil
    lastReconcile=nil
end
local function available(object,passive)
    if not G.visible() then return "Grid control is unavailable for this world." end
    local s=store()
    if not passive and not reconcile(s) or s.standDown then return s.standDown end
    if not SC.Terminal or not SC.Terminal.isComputer(object) or not U().present(object) then
        return "The computer is no longer here."
    end
    if not unlocked(object) then return "Unlock this computer first." end
    if not identity(object) then return "This computer's identity is unreadable." end
end
function G.connectBlocker(object,passive)
    local reason=available(object,passive)
    if reason then return reason end
    local site=G.siteFor(object)
    if not site then return "Place this computer within 40 tiles of a substation." end
    local state,p,s=hardware(object),portable(object),store()
    if state and state.gridSite then return "This computer is permanently connected to its substation." end
    if s.sites[site.id] then return "This substation is already answering." end
    local own=s.connections[site.id]
    if own and own.controller~=identity(object) then return "Another computer is connecting to this substation." end
    local pending=0 for _ in pairs(s.connections) do pending=pending+1 end
    if not own and counts(s)+pending>=G.MAX_LINKS then return "Five substations is the maximum." end
    if p and p[G.CRACK_KEY] then return "Finish this computer's crack before leaving it at a substation." end
    if not radio(state) then return "Mount a working two-way walkie-talkie first." end
    if own and own.radioId~=state.radio.id then return "Restore the original mounted radio to resume this connection." end
    if state.on==false then return "Switch the computer on first." end
    local power=SC.TerminalWorld.powerState(U().square(object))
    if power.generator~=true then return "A running generator must power this computer; a battery or grid supply is insufficient." end
end
function G.startConnect(object)
    local reason=G.connectBlocker(object)
    if reason then return false,reason end
    local p,site=portable(object),G.siteFor(object)
    if p[G.CONNECT_KEY] then return false,"Connection is already in progress." end
    local x,y,z=U().position(object)
    local task={site=site.id,doneHours=0,controller=identity(object),lastHours=clock(),powered=true,
        radioId=hardware(object).radio.id,x=x,y=y,z=z}
    p[G.CONNECT_KEY]=task store().connections[site.id]=task known[task.controller]=object
    return true,"Connecting to "..site.label..". Keep the generator running for 30 game minutes."
end
function G.yardSupply(object,state)
    if not state or not byId[state.gridSite] or not supported() then return false end
    local s=store()
    local site=state and byId[state.gridSite]
    local row=s and site and s.sites[site.id]
    return row~=nil and state.on~=false and G.siteFor(object)==site
        and row.controller==identity(object) and radio(state) and row.radioId==state.radio.id
end
function G.pinned(object)
    local state=hardware(object)
    G.restoreInstallation(object,state)
    if state and state.gridSite~=nil then return true end
    -- The confirmation commits this exact assembly, including setup time.
    -- Moving it or exchanging its radio mid-connection must not strand a link.
    if cached and validate(cached) then
        local id=identity(object)
        for _,task in pairs(cached.connections) do if task.controller==id then return true end end
    end
    return false
end
function G.restoreInstallation(object,state)
    if not cached or not state or state.gridSite~=nil or not radio(state) or not validate(cached) then return end
    local id=identity(object)
    for site,row in pairs(cached.sites) do
        if row.controller==id and row.radioId==state.radio.id and G.siteFor(object)==byId[site] then
            state.gridSite=site return
        end
    end
end
function G.bestSkill(player)
    local level=U().skill(player)
    local base=SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if SC.Registry and type(SC.Registry.living)=="function" then
        local checked=0
        for _,actor in ipairs(SC.Registry.living()) do
            checked=checked+1 if checked>256 then break end
            if SC.BaseLife and type(SC.BaseLife.resident)=="function" then
                local id=SC.Registry.idOf(actor)
                local resident=SC.BaseLife.resident(id)
                if resident and base and resident.baseId==base.id
                    and (not SC.GameplayUtil.isDead or not SC.GameplayUtil.isDead(actor)) then
                    level=math.max(level,U().skill(actor))
                end
            end
        end
    end
    return level
end
local function remoteBlocker(object,cracking,passive)
    local reason=available(object,passive)
    if reason then return reason end
    if G.siteFor(object) then return "Use a computer outside substation areas." end
    if cracking and (not SC.BaseLife or SC.BaseLife.isInside(object)~=true) then
        return "Run the controller crack from a computer inside camp."
    end
    if not radio(hardware(object)) then return "Mount a working two-way walkie-talkie first." end
    if not SC.TerminalHardware.powered(object) then return "This computer needs power." end
end
function G.startCrack(object,player,siteId)
    local reason=remoteBlocker(object,true)
    if reason then return false,reason end
    local s,p=store(),portable(object)
    local site=byId[siteId]
    local row=site and s.sites[site.id]
    if not row or row.online then return false,"Choose a linked substation whose controller is still locked." end
    if p[G.CRACK_KEY] or p[G.CONNECT_KEY] then return false,"This computer already has a controller task." end
    local skill=G.bestSkill(player)
    local id=identity(object)
    if not id then return false,"This computer's identity is unreadable." end
    local count=0
    for _ in pairs(s.jobs) do count=count+1 end
    if count>=16 then return false,"Finish an existing controller task first." end
    local x,y,z=U().position(object)
    local task={site=site.id,controller=id,requiredHours=skill>=8 and 72 or skill>=4 and 96 or 120,
        doneHours=0,lastHours=clock(),powered=true,notified={},x=x,y=y,z=z}
    s.jobs[id]=task p[G.CRACK_KEY]={site=site.id,controller=id}
    known[id]=object
    return true,"Cracking "..site.label..". Keep this base computer powered; progress survives outages."
end
local function energizeBlocker(s)
    if s.on then return "The grid is already running." end
    local _,online=counts(s)
    if online<1 then return "Crack at least one linked substation first." end
    local days=age()
    if not finite(days) or days<=s.originalShut then return "The original power grid is still running." end
    if s.lockedUntilCold then return "The tripped breaker must cool to 0% before restart." end
    if s.heat+5>=100 then return "The grid is too hot to start." end
end
function G.energize(object,player)
    local reason=remoteBlocker(object,false)
    if reason then return false,reason end
    local s=store() advance(s,clock())
    reason=energizeBlocker(s)
    if reason then return false,reason end
    local days=age()
    local window=G.bestSkill(player)>=8 and 48 or 24
    local heat=s.heat+5
    local remaining=(100-heat)/(95/window)
    local value=math.min(math.floor(days)+3,math.floor(days)+math.ceil(remaining/24)+1)
    if not write(s,value) then return false,s.standDown end
    s.on,s.heat,s.windowHours,s.warned,s.heatHours=true,heat,window,{},clock()
    notice("Grid power restored. "..math.floor(remaining).." game hours until the heat limit.")
    return true,"The grid is on. Watch the heat gauge; switching off early shortens cooling."
end
function G.cut(reason)
    if not G.visible() then return false,"Grid control is unavailable." end
    local s=store()
    if not reconcile(s) then return false,s.standDown end
    advance(s,clock())
    if not s.on then return false,"The grid is already off." end
    return cutOwned(s,reason)
end
local function jobObject(task)
    local object=known[task.controller]
    if object and U().present(object) and identity(object)==task.controller then return object end
    known[task.controller]=nil
    local cell=type(getCell)=="function" and getCell()
    local square=U().call(cell,"getGridSquare",task.x,task.y,task.z)
    if not square then return nil,"unloaded" end -- lookup never loads an absent chunk
    for _,candidate in ipairs(U().list(U().call(square,"getObjects"),64)) do
        if identity(candidate)==task.controller and U().present(candidate) then
            known[task.controller]=candidate return candidate
        end
    end
    return nil,"missing"
end
local function sampleConnection(s,task,hours)
    local object,source=jobObject(task)
    local p=object and portable(object)
    local delta=math.max(0,hours-task.lastHours)
    local wasPowered=task.powered
    if source=="missing" then task.powered=false end
    if object then task.powered=G.siteFor(object)==byId[task.site] and G.connectBlocker(object,true)==nil end
    task.lastHours=math.max(task.lastHours,hours)
    if wasPowered and task.powered then task.doneHours=math.min(0.5,task.doneHours+delta) end
    if task.doneHours>=0.5 then
        local site=byId[task.site]
        s.connections[site.id]=nil
        s.sites[site.id]={linkedAt=hours,online=false,announced=false,controller=task.controller,radioId=task.radioId}
        if object then
            local state=hardware(object)
            state.gridSite=site.id
            if p then p[G.CONNECT_KEY]=nil end
        end
        notice(site.label.." is answering. Run its controller crack from a base computer.")
    end
end
local function sampleJob(s,task,hours)
    local row=s.sites[task.site]
    if not row then return end
    local object,source=jobObject(task)
    local p=object and portable(object)
    if row.online then
        s.jobs[task.controller]=nil
        if p then p[G.CRACK_KEY]=nil end
        return
    end
    local delta=math.max(0,hours-task.lastHours)
    if source=="missing" then task.powered=false end
    -- The player selected last-known-supply catch-up. No service observes a
    -- closed PC; this arithmetic runs only during a computer/radio interaction.
    if task.powered then task.doneHours=math.min(task.requiredHours,task.doneHours+delta) end
    task.lastHours=math.max(task.lastHours,hours)
    if object then
        local marker=p and p[G.CRACK_KEY]
        local bound=type(marker)=="table" and marker.site==task.site and marker.controller==task.controller
        task.powered=bound and remoteBlocker(object,true,true)==nil or false
        task.x,task.y,task.z=U().position(object)
    end
    local percent=task.doneHours/task.requiredHours*100
    for _,milestone in ipairs({25,50,75,100}) do
        if percent>=milestone and not task.notified[milestone] then
            task.notified[milestone]=true
            notice(byId[task.site].label.." controller passed the "..milestone.."% checkpoint.")
        end
    end
    if task.doneHours>=task.requiredHours then
        advance(s,hours) row.online=true s.jobs[task.controller]=nil
        if p then p[G.CRACK_KEY]=nil end
        notice(byId[task.site].label.." is online. Its controller is yours.")
    end
end
function G.sample(object)
    if not G.visible() then return end
    local s,hours=store(),clock()
    if not finite(hours) or not reconcile(s) then return end
    advance(s,hours)
    if object then
        local id=identity(object)
        if id then known[id]=object end
        local state=hardware(object)
        G.restoreInstallation(object,state)
        local p=portable(object)
        local marker=p and p[G.CONNECT_KEY]
        if type(marker)=="table" and s.sites[marker.site] and s.sites[marker.site].controller==id then p[G.CONNECT_KEY]=nil end
        local crack=p and p[G.CRACK_KEY]
        if type(crack)=="table" and crack.controller==id and not s.jobs[id]
            and s.sites[crack.site] and s.sites[crack.site].online then
            -- A different terminal can finish this task while its PC is unloaded.
            p[G.CRACK_KEY]=nil
        end
    end
    local pending={}
    for id in pairs(s.connections) do pending[#pending+1]=id end
    for _,id in ipairs(pending) do sampleConnection(s,s.connections[id],hours) end
    local ids={}
    for id in pairs(s.jobs) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do sampleJob(s,s.jobs[id],hours) end
end
function G.pauseComputer(object)
    if not cached or not G.visible() then return end
    G.sample(object)
    local s,id=store(),identity(object)
    local task=id and s.jobs[id]
    if task then task.powered=false task.lastHours=clock() or task.lastHours end
    for _,connection in pairs(s.connections) do
        if connection.controller==id then connection.powered=false connection.lastHours=clock() or connection.lastHours end
    end
    known[id or false]=nil
end
function G.snapshot(object)
    if not supported() then return {visible=false,reason="Grid control is single-player only."} end
    local s=store()
    if not s then return {visible=false,reason="Grid control records are unreadable; they have been preserved."} end
    if s.originalShut>=100000 then return {visible=false,reason="The power grid never shuts off in this world."} end
    G.sample(object)
    local linked,online=counts(s)
    local hours,days=clock(),age()
    local p=object and portable(object)
    local task=s.jobs[identity(object) or false]
    local marker=p and p[G.CONNECT_KEY]
    local connection=type(marker)=="table" and s.connections[marker.site]
    if connection and connection.controller~=identity(object) then connection=nil end
    local nearest,distance
    local x,y
    if object then x,y=U().position(object) end
    if x and linked<G.MAX_LINKS then
        for _,site in ipairs(G.SITES) do
            if not s.sites[site.id] then
                local d=(x-site.x)^2+(y-site.y)^2
                if not distance or d<distance then nearest,distance=site,d end
            end
        end
    end
    local rows={}
    for _,site in ipairs(G.SITES) do
        local row=s.sites[site.id]
        local progress
        for _,job in pairs(s.jobs) do
            if job.site==site.id and (not progress or job.doneHours>progress.doneHours) then progress=job end
        end
        rows[#rows+1]={id=site.id,label=site.label,x=site.x,y=site.y,
            linked=row~=nil,online=row and row.online==true or false,crack=progress}
    end
    local blocked=object and remoteBlocker(object,false)
    return {visible=true,on=s.on,heat=s.heat,locked=s.lockedUntilCold,standDown=s.standDown,
        linked=linked,online=online,maxLinks=G.MAX_LINKS,cooldownDays=cooldown(s),sites=rows,
        originalShut=s.originalShut,daysLeft=days and math.max(0,s.originalShut-days),
        remainingHours=s.on and (100-s.heat)/(95/s.windowHours) or 0,
        coolingHours=s.heat/(100/(cooldown(s)*24)),site=object and G.siteFor(object),
        nearest=nearest,distance=distance and math.floor(math.sqrt(distance)),blocker=blocked,
        crack=validJob(task) and {site=task.site,label=byId[task.site].label,
            doneHours=task.doneHours,requiredHours=task.requiredHours,
            percent=task.doneHours/task.requiredHours*100,paused=remoteBlocker(object,true,true)} or nil,
        connecting=validConnection(connection) and {site=connection.site,
            percent=connection.doneHours/0.5*100,blocker=G.connectBlocker(object)} or nil}
end
function G.announce(object)
    if not G.visible() or G.siteFor(object) then return {} end
    local result,s={},store()
    for _,site in ipairs(G.SITES) do
        local row=s.sites[site.id]
        if row and not row.announced then
            result[#result+1]=site.label.." is answering. It will not let me in yet. Start its crack from a base computer."
            row.announced=true
        end
    end
    return result
end
function G.markNearest(object,snapshot)
    local snap=snapshot or G.snapshot(object)
    local site=snap.nearest
    if not site or not SC.FactionLife or type(SC.FactionLife.addMapAnnotation)~="function" then return false end
    local s=store()
    local text="Substation: "..site.label
    if s.marked[site.id] then return true end
    local okay,accepted=pcall(SC.FactionLife.addMapAnnotation,text,site.x,site.y,{r=0.85,g=0.70,b=0.30})
    if okay and accepted~=false then s.marked[site.id]=text return true end
    return false
end
function G.prepare(window,proposal)
    local op=proposal.operation
    if op~="connect" and op~="crack" and op~="energize" and op~="cut" then return nil,"Unknown grid request." end
    G.sample(window.object)
    local reason
    if op=="connect" then reason=G.connectBlocker(window.object)
    else reason=remoteBlocker(window.object,op=="crack") end
    if reason then return nil,reason end
    local s=store()
    local site=proposal.site and byId[proposal.site]
    if op=="crack" and (not site or not s.sites[site.id] or s.sites[site.id].online) then
        return nil,"Choose a linked substation whose controller is still locked."
    end
    if op=="cut" and not s.on then return nil,"The grid is already off." end
    if op=="energize" then
        reason=energizeBlocker(s)
        if reason then return nil,reason end
    end
    local target={object=window.object,identity=identity(window.object),operation=op,site=proposal.site}
    local prompt=op=="connect" and "Permanently connect THIS computer and its mounted radio to the substation? They stay here for good. Keep a generator running for 30 game minutes. [Y/N]"
        or op=="crack" and ("Start cracking "..site.label.." from this base computer? Power loss pauses progress; each substation needs its own crack. [Y/N]")
        or op=="cut" and "Switch the restored grid off now and begin cooling? [Y/N]"
        or "Energize the grid? Starting adds 5% heat. The breaker will trip at 100%. [Y/N]"
    return target,prompt
end
function G.execute(window,target)
    if target.object~=window.object or target.identity~=identity(window.object) then return false,"The computer changed. Ask again." end
    if target.operation=="connect" then return G.startConnect(window.object) end
    if target.operation=="crack" then return G.startCrack(window.object,window.player,target.site) end
    if target.operation=="energize" then return G.energize(window.object,window.player) end
    local reason=remoteBlocker(window.object,false)
    if reason then return false,reason end
    return G.cut()
end
function G.reset()
    cached,lastReconcile=nil,nil
    known=setmetatable({}, {__mode="v"})
    fallback,notices,serial={},{},0
end
return G
