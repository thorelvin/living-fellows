-- SPDX-License-Identifier: MIT
local T,G=GRID_TEST,SurvivorCompanion.GridControl
local check=T.check
T.reset()
check(G.visible(),"ordinary single-player worlds offer grid control")
check(T.bucket.originalShut==26,"capture exact original setting before writing")
for _,site in ipairs(G.SITES) do
    local pc=T.pc(site.x+40,site.y,false)
    check(G.siteFor(pc)==site,"40-tile boundary includes "..site.id)
    pc.square.x=site.x+40.1
    check(G.siteFor(pc)==nil,"outside boundary rejects "..site.id)
end
local yard,site=T.link()
check(G.yardSupply(yard,yard.hardware)==true,"bound yard PC powers itself")
local other=T.pc(site.x,site.y,false)
other.hardware.gridSite=site.id
check(not G.yardSupply(other,other.hardware),"another PC cannot copy the free yard supply")
yard.hardware.on=false
check(not G.yardSupply(yard,yard.hardware),"physical off switch wins")
yard.hardware.on=true yard.square.x=site.x+41
check(not G.yardSupply(yard,yard.hardware),"yard supply remains within its own site")
yard.square.x=site.x
check(G.pinned(yard),"connected equipment remains pinned")
check(G.startConnect(yard)==false,"cannot connect twice")
local home=T.pc(12000,6800,true)
check(G.startCrack(yard,{skill=8},site.id)==false,"yard supply cannot run its own crack")
check(G.startCrack(other,{skill=8},site.id)==false,"outside PCs cannot begin base cracking")
local offsite=T.pc(11900,6800,false)
check(G.startCrack(offsite,{skill=8},site.id)==false,"an off-site computer still needs to be inside camp to crack")
local player={skill=0}
home.hardware.radio=nil
check(G.startCrack(home,player,site.id)==false,"cracking needs a mounted radio")
home.hardware.radio={id=99}
check(G.startCrack(home,player,site.id),"base radio PC starts a controller crack")
local task=T.bucket.jobs[home.md.movableData.LF_LarchOS.identity]
check(task.requiredHours==120,"low Electrical needs five game days")
local clocks,power,grid,reads=T.clocks,T.powerReads,T.squareReads,T.reads
T.step(24)
for _=1,1000 do G.pulse() end
check(T.clocks==clocks and T.powerReads==power and T.squareReads==grid and T.reads==reads,
    "idle cracks perform zero clock, grid, sandbox or power reads")
check(task.doneHours==0,"idle timer does no cracking work")
G.snapshot(home)
check(T.near(task.doneHours,24),"contacting EMMA settles elapsed game time")
home.powered=false T.step(6) G.snapshot(home)
local preserved=task.doneHours
T.step(12) G.snapshot(home)
check(T.near(task.doneHours,preserved),"known power loss pauses without rollback")
home.powered=true G.snapshot(home) T.step(6) G.snapshot(home)
check(T.near(task.doneHours,preserved+6),"power restoration resumes earned progress")
G.pauseComputer(home) T.step(20)
home.present=false
G.snapshot(nil)
check(T.near(task.doneHours,preserved+6),"carrying a PC earns no progress")
home.present=true G.snapshot(home) T.step(2) G.snapshot(home)
check(T.near(task.doneHours,preserved+8),"placed machine resumes after power is observed")
T.step(120) G.snapshot(home)
check(T.bucket.sites[site.id].online and T.empty(T.bucket.jobs),"first completion publishes one online site")
local before=T.bucket.sites[site.id]
G.snapshot(home)
check(T.bucket.sites[site.id]==before,"completion is idempotent")
for _,skill in ipairs({0,4,7,8,10}) do
    T.reset() local _,linked=T.link()
    local pc=T.pc(12000,6800,true)
    check(G.startCrack(pc,{skill=skill},linked.id),"start at Electrical "..skill)
    local job=T.bucket.jobs[pc.md.movableData.LF_LarchOS.identity]
    check(job.requiredHours==(skill>=8 and 72 or skill>=4 and 96 or 120),"fixed crack duration at skill "..skill)
end
for _,skill in ipairs({0,8}) do
    local pc,who=T.ready(skill)
    check(G.energize(pc,who),"energize at Electrical "..skill)
    local s=T.bucket
    check(T.near(s.heat,5),"starting surge is five percent")
    check(T.shut<=math.floor(getWorld():getWorldAgeDays())+3,"bounded native shutoff lease")
    local duration=skill>=8 and 48 or 24
    T.step(duration-0.01) G.pulse()
    check(s.on and s.heat<100,"full run does not trip early")
    T.step(0.01) G.pulse()
    check(not s.on and s.lockedUntilCold and T.near(s.heat,100),"full run trips exactly at "..duration.." hours")
    check(T.shut==26,"trip restores the exact original sandbox value")
    check(not G.energize(pc,who),"tripped breaker cannot restart warm")
    T.step(7*24-0.01) G.snapshot(pc)
    check(s.lockedUntilCold,"lock lasts until completely cold")
    T.step(0.01) G.snapshot(pc)
    check(T.near(s.heat,0) and not s.lockedUntilCold,"cold state releases lock")
end
for sites=1,5 do
    local pc,who=T.ready(0,sites)
    check(G.snapshot(pc).cooldownDays==8-sites,"online sites improve cooldown to "..(8-sites).." days")
    check(G.energize(pc,who),"start with "..sites.." online sites")
    T.step(6) G.pulse()
    check(T.near(T.bucket.heat,28.75),"six-hour heat includes the starting surge")
    check(G.cut(),"early switch-off succeeds")
    T.step(1) G.snapshot(pc)
    check(T.near(T.bucket.heat,28.75-100/((8-sites)*24)),"partial cooling uses the site's actual rate")
    check(G.energize(pc,who),"warm restart is allowed before a trip")
end
local pc,who=T.ready(8)
check(G.energize(pc,who),"foreign-value control starts with our lease")
T.shut=9999 T.step(0.1)
local writes=T.writes
G.pulse()
check(T.bucket.standDown~=nil and T.writes==writes and T.shut==9999,"foreign ownership never gets overwritten")
T.shut=T.bucket.written T.step(0.1) G.pulse()
check(T.bucket.standDown==nil,"matching setting restores our ownership")
T.shut=T.bucket.originalShut T.step(0.1) G.pulse()
check(not T.bucket.on and T.bucket.standDown==nil and T.shut==26,
    "a lost native lease is accepted as off without forcing power back on")
T.crew={{id="home",skill=8},{id="foreign",skill=10},{id="dead",skill=10,dead=true}}
T.residents={home={baseId="base"},foreign={baseId="other"},dead={baseId="base"}}
SurvivorCompanion.BaseLife.active=function() return {id="base"} end
check(G.bestSkill({skill=2})==8,"only living residents of the active camp contribute Electrical")
T.reset(100000)
check(not G.visible() and T.writes==0,"never-shuts worlds stay untouched")
T.reset() T.client=true
check(not G.visible() and T.bucket==nil,"multiplayer fails closed before record creation")
T.reset() T.bucket={schema=999,originalShut=26}
check(not G.visible() and T.bucket.schema==999,"unknown schema is preserved")
T.reset() G.visible() T.bucket.heat=0/0
check(not G.visible(),"malformed numeric state is preserved and disabled")
T.reset()
local raw={schema=5,keep="original"} T.bucket=raw G.restore()
G.pulse()
check(T.bucket==raw and raw.keep=="original" and T.writes==0,"restore never overwrites unreadable data")
T.reset()
local emptyReads=T.reads
G.pulse()
check(T.bucket==nil and T.reads==emptyReads,"untouched worlds pay no idle grid cost")
T.reset()
local _,linked=T.link()
local station=T.pc(12000,6800,true)
check(G.startCrack(station,{skill=8},linked.id),"lifecycle controller task starts")
local id=station.md.movableData.LF_LarchOS.identity
local saved=T.bucket.jobs[id]
T.step(5) G.sample(station)
check(T.near(saved.doneHours,5),"initial work is verified on contact")
G.reset() G.restore()
T.step(7) G.sample(station)
check(T.near(saved.doneHours,12),"save/reload resumes the same canonical task")
local beforeReads=T.powerReads
station.present=false T.tiles["12000:6800:0"]=nil
T.step(24) G.snapshot(nil)
check(T.near(saved.doneHours,36) and T.powerReads==beforeReads,
    "unloaded catch-up uses last known supply without a world power survey")
local square=station.square
T.tiles["12000:6800:0"]=square square.objects={}
T.step(2) G.snapshot(nil)
check(T.near(saved.doneHours,36) and saved.powered==false,
    "a loaded empty location proves the old machine is missing and pauses its work")
station.present=true square.objects={station}
G.sample(station) T.step(1) G.sample(station)
check(T.near(saved.doneHours,37),"the same physical machine can resume a paused task")
local earned=saved.doneHours
T.step(-3) G.sample(station)
check(T.near(saved.doneHours,earned),"clock rollback never deletes or repeats earned hours")
T.reset()
for index=1,5 do T.link(index) end
local sixth=G.SITES[6]
local extra=T.pc(sixth.x,sixth.y,false)
check(not G.startConnect(extra),"sixth controller is refused before taking its equipment")
T.reset()
local first=G.SITES[1]
local pending=T.pc(first.x,first.y,false)
pending.square.generator=false
check(not G.startConnect(pending),"battery power never satisfies generator-only setup")
pending.square.generator=true
check(G.startConnect(pending),"event-driven setup starts")
pending.present=false T.tiles[first.x..":"..first.y..":0"]=nil
T.step(0.5) G.snapshot(nil)
check(T.bucket.sites[first.id]~=nil,"base contact settles an unloaded substation setup")
pending.present=true T.tiles[first.x..":"..first.y..":0"]=pending.square
pending.hardware.gridSite=nil
G.restoreInstallation(pending,pending.hardware)
check(G.yardSupply(pending,pending.hardware),"late-loaded site restores only its bound computer's supply")
T.reset()
local unknown=T.pc(first.x,first.y,false)
unknown.md.movableData.LF_LarchOS.identity=nil
check(not G.startConnect(unknown) and T.empty(T.bucket.connections),"unreadable PC identity cannot create a malformed connection")
local unready=T.pc(12000,6800,true)
local target,why=G.prepare({object=unready,player={skill=0}},{operation="energize"})
check(target==nil and why:find("Crack at least one",1,true)~=nil,"unavailable start explains the prerequisite before confirmation")
T.reset()
local reconnect=T.pc(first.x,first.y,false)
check(G.startConnect(reconnect),"connection persistence fixture starts")
local marker={} for key,value in pairs(reconnect.md.movableData[G.CONNECT_KEY]) do marker[key]=value end
reconnect.md.movableData[G.CONNECT_KEY]=marker -- separately deserialized object/world buckets
G.reset() G.restore() T.step(.25)
check(T.near(G.snapshot(reconnect).connecting.percent,50) and marker.doneHours==0,
    "reloaded connection displays canonical progress rather than its portable checkpoint copy")
T.step(.25) G.sample(reconnect)
local terminal=T.pc(12000,6800,true)
check(G.startCrack(terminal,{skill=8},first.id),"unloaded completion fixture starts")
terminal.present=false T.tiles["12000:6800:0"]=nil
T.step(72) G.snapshot(nil)
check(T.bucket.sites[first.id].online and terminal.md.movableData[G.CRACK_KEY]~=nil,
    "remote contact completes the canonical job without touching unloaded furniture")
terminal.present=true T.tiles["12000:6800:0"]=terminal.square
G.sample(terminal)
check(terminal.md.movableData[G.CRACK_KEY]==nil,"returning to the original PC clears its completed portable task")
T.reset()
local assembling=T.pc(first.x,first.y,false)
check(G.startConnect(assembling) and G.pinned(assembling) and not G.yardSupply(assembling,assembling.hardware),
    "confirmation pins the exact assembly during setup, before free yard power is granted")
local oldRadio=assembling.hardware.radio.id
assembling.hardware.radio.id=oldRadio+100
T.step(1) G.sample(assembling)
check(not T.bucket.sites[first.id] and G.connectBlocker(assembling):find("original mounted radio",1,true)~=nil,
    "an externally exchanged radio cannot publish a link bound to the wrong item")
assembling.hardware.radio.id=oldRadio
G.sample(assembling) T.step(.5) G.sample(assembling)
check(G.yardSupply(assembling,assembling.hardware),"restoring the exact radio resumes and completes setup safely")
SC_TEST_REPORT="GRID_CONTROL_PASS checks="..T.checks
