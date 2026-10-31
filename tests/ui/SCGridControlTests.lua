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
check(T.near(task.doneHours,24),"a computer found without power earns nothing for the time since the last look")
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
check(T.near(saved.doneHours,12) and T.powerReads==beforeReads,
    "an unloaded machine earns nothing yet and costs no world power survey")
station.present=true T.tiles["12000:6800:0"]=station.square
T.step(1) G.sample(station)
check(T.near(saved.doneHours,37),"returning to a machine that still has power credits the whole absence")
local square=station.square
station.present=false square.objects={}
T.step(2) G.snapshot(nil)
check(T.near(saved.doneHours,37) and saved.powered==false,
    "a loaded empty location proves the old machine is missing and pauses its work")
station.present=true square.objects={station}
G.sample(station) T.step(1) G.sample(station)
check(T.near(saved.doneHours,38),"the same physical machine can resume a paused task")
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
check(not T.bucket.sites[first.id].online,"remote contact cannot finish a crack nobody can see is powered")
terminal.present=true T.tiles["12000:6800:0"]=terminal.square
G.sample(terminal)
check(T.bucket.sites[first.id].online and terminal.md.movableData[G.CRACK_KEY]==nil,
    "returning to the powered PC finishes the crack and clears its portable task")
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

-- A generator that dies mid-crack costs the time since the last look, never finished work.
T.reset()
local _,outage=T.link()
local camp=T.pc(12000,6800,true)
check(G.startCrack(camp,{skill=0},outage.id),"outage fixture starts")
local outageJob=T.bucket.jobs[camp.md.movableData.LF_LarchOS.identity]
camp.powered=false T.step(120) G.sample(camp)
check(T.near(outageJob.doneHours,0) and not T.bucket.sites[outage.id].online,
    "a crack cannot finish on a computer that has no power at contact")
camp.powered=true G.sample(camp) T.step(10) G.sample(camp)
check(T.near(outageJob.doneHours,10),"restored power earns time from the moment it is seen again")
camp.powered=false T.step(30) G.sample(camp)
camp.powered=true G.sample(camp)
check(T.near(outageJob.doneHours,10),"an outage keeps what was already banked")

-- A computer destroyed during setup frees the site and its slot.
T.reset()
local gone=T.pc(first.x,first.y,false)
check(G.startConnect(gone),"lost connection fixture starts")
local goneMarker=gone.md.movableData[G.CONNECT_KEY]
gone.present=false gone.square.objects={}
local spare=T.pc(first.x+1,first.y,false)
check(G.connectBlocker(spare):find("Another computer",1,true)~=nil,"a live setup still holds the site before contact")
G.snapshot(nil)
check(T.bucket.connections[first.id]==nil,"a machine proven gone releases its connection")
check(G.connectBlocker(spare)==nil and G.startConnect(spare),"a replacement can connect after the loss")
T.step(.5) G.sample(spare)
check(T.bucket.sites[first.id]~=nil,"the replacement completes the link")
gone.present=true gone.square.objects={gone}
gone.md.movableData[G.CONNECT_KEY]=goneMarker
G.sample(gone)
check(gone.md.movableData[G.CONNECT_KEY]==nil,"a stale connection marker is cleared if the machine comes back")
T.reset()
local unseen=T.pc(first.x,first.y,false)
check(G.startConnect(unseen),"unloaded connection fixture starts")
T.tiles[first.x..":"..first.y..":0"]=nil
unseen.present=false
G.snapshot(nil)
check(T.bucket.connections[first.id]~=nil,"an unloaded machine is not assumed destroyed")

-- A lost cracking computer hands its checkpoint to a replacement.
T.reset()
local _,taken=T.link()
local oldPc=T.pc(12000,6800,true)
check(G.startCrack(oldPc,{skill=0},taken.id),"takeover fixture starts")
local oldId=oldPc.md.movableData.LF_LarchOS.identity
T.step(30) G.sample(oldPc)
local newPc=T.pc(12001,6800,true)
local who={object=newPc,player={skill=8}}
local denied,busyWhy=G.prepare(who,{operation="crack",site=taken.id})
check(denied==nil and busyWhy:find("already cracking",1,true)~=nil,"a working computer keeps its site")
check(not G.startCrack(newPc,{skill=8},taken.id),"a direct start cannot duplicate live work")
oldPc.present=false oldPc.square.objects={}
T.step(50)
local row
for _,candidate in ipairs(G.snapshot(newPc).sites) do if candidate.id==taken.id then row=candidate end end
check(row.crack and row.crack.lost==true and T.near(row.crack.doneHours,30),"the status page reports the lost machine")
local prepared,prompt=G.prepare(who,{operation="crack",site=taken.id})
check(prepared~=nil and prompt:find("25.0%",1,true)~=nil,"the replacement is offered the saved checkpoint")
check(G.startCrack(newPc,{skill=8},taken.id),"the replacement takes over")
local newId=newPc.md.movableData.LF_LarchOS.identity
local adopted=T.bucket.jobs[newId]
check(T.bucket.jobs[oldId]==nil and T.near(adopted.doneHours,30) and adopted.requiredHours==120,
    "progress and duration carry over without the lost machine's record")
T.step(90) G.sample(newPc)
check(T.bucket.sites[taken.id].online,"the replacement finishes the job")
oldPc.present=true oldPc.square.objects={oldPc}
G.sample(oldPc)
check(oldPc.md.movableData[G.CRACK_KEY]==nil,"the old machine is released if it ever returns")
T.reset()
local _,back=T.link()
local carried=T.pc(12000,6800,true)
check(G.startCrack(carried,{skill=0},back.id),"carried fixture starts")
carried.present=false carried.square.objects={}
G.snapshot(nil)
carried.present=true carried.square.objects={carried}
G.sample(carried)
check(T.bucket.jobs[carried.md.movableData.LF_LarchOS.identity].lost==nil,"a machine that comes back stops counting as lost")

-- Warnings reach the player away from the grid page, and survive a reload.
local warned,warnedBy=T.ready(0)
check(G.energize(warned,warnedBy),"warning fixture starts")
G.takeNotices() T.halos={}
T.step(23.9) G.pulse()
check(T.bucket.warned[75] and T.bucket.warned[90] and #T.halos>=2,"heat warnings show with every computer closed")
check(T.halos[1]:find("EMMA: Grid heat 75%",1,true)==1,"the warning is in EMMA's name")
G.reset() G.restore()
local unread=G.takeNotices()
check(#unread>=2 and unread[1]:find("75%",1,true)~=nil,"unread warnings survive save and reload")
check(#G.takeNotices()==0,"each warning is read once")
T.halos={}
T.step(0.2) G.pulse()
check(T.bucket.lockedUntilCold and T.halos[#T.halos]:find("breaker tripped",1,true)~=nil,"the breaker trip reaches a player far from any computer")
-- An open screen prints the notice itself, and an unread pile stays bounded.
local cycled,cycledBy=T.ready(0)
G.takeNotices() T.halos={}
SurvivorCompanion.Terminal.window={closed=false}
for _=1,8 do
    check(G.energize(cycled,cycledBy),"notice cap fixture starts")
    check(G.cut("Switched off."),"notice cap fixture stops")
end
check(#T.halos==0,"an open computer screen does not also show a halo")
SurvivorCompanion.Terminal.window={closed=true}
check(G.energize(cycled,cycledBy) and #T.halos==1,"a closed window no longer counts as an open screen")
SurvivorCompanion.Terminal.window=nil
local pile=G.takeNotices()
check(#pile==G.MAX_UNREAD and pile[#pile]:find("Grid power restored",1,true)==1,"the unread pile keeps the newest notices")
check(#G.takeNotices()==0,"an emptied pile reads as empty")

-- A lease that outlived its record: map_sand.bin saved, global_mod_data.bin did not.
local paired,pairedBy=T.ready(0)
check(G.energize(paired,pairedBy),"paired-save fixture starts")
local lease=T.shut
T.bucket.on=false T.bucket.written=nil T.bucket.writeIntent=nil
G.reset() G.restore()
check(G.snapshot(paired).standDown~=nil and T.shut==lease,"a live unknown lease is left alone")
T.step((lease-T.days+2)*24)
local recovered=G.snapshot(paired)
check(recovered.standDown==nil and T.shut==T.bucket.originalShut and T.bucket.on==false,
    "once the lease has run out the controls recover by themselves")
check(G.energize(paired,pairedBy),"the grid can be started again after recovery")
T.reset(26) G.visible()
T.shut=200
T.step(24*30) G.snapshot(nil)
check(T.bucket.standDown~=nil and T.shut==200,"a foreign future date is never overwritten, however long it waits")
T.reset() G.visible()
T.shut=8
G.snapshot(nil)
check(T.bucket.standDown~=nil and T.shut==8,"a value below the recorded original is not ours to take back")
T.reset() G.visible()
T.bucket.writeIntent=44 T.shut=44
check(G.snapshot(nil).standDown==nil and T.shut==26 and T.bucket.writeIntent==nil,
    "a journalled write that never finished is rolled back")
T.reset() G.visible()
T.bucket.writeIntent=44 T.shut=45
check(G.snapshot(nil).standDown~=nil and T.shut==45,"the journal only proves its exact value")

-- A camp computer near a substation keeps its ordinary role until it is connected.
T.reset()
local campPc=T.pc(first.x+5,first.y,true)
check(G.siteFor(campPc)==first and G.yardFor(campPc)==nil,"a camp computer near a substation is not a yard computer")
local yardPc=T.pc(first.x-5,first.y,false)
check(G.yardFor(yardPc)==first,"a computer outside any camp is a yard computer")
local campSnap=G.snapshot(campPc)
check(campSnap.site==nil and campSnap.connectable==first and campSnap.blocker==nil,"the camp computer keeps grid control and may offer to connect")
local camped=T.pc(first.x+6,first.y,true)
check(G.startConnect(camped),"the camp computer can still be connected deliberately")
check(G.yardFor(camped)==first,"accepting the connection makes it a yard computer")
T.step(.5) G.sample(camped)
check(camped.hardware.gridSite==first.id and G.yardFor(camped)==first and G.snapshot(camped).site==first,"a connected camp computer stays a yard computer")
check(G.snapshot(campPc).connectable==nil,"a linked site no longer offers another connection")
check(G.startCrack(campPc,{skill=0},first.id),"an unconnected camp computer beside the yard can run the crack")
check(not G.startCrack(camped,{skill=0},first.id),"the connected machine still cannot crack itself")
SC_TEST_REPORT="GRID_CONTROL_PASS checks="..T.checks
