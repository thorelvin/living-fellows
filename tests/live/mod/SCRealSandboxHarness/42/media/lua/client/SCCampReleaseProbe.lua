-- SPDX-License-Identifier: MIT
-- Real camp AI stays enabled. Controlled vitals/items exist only in this clone.
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
local P={} SCRealSandboxHarnessProbes.SCCampReleaseProbe=P
local function S() return SurvivorCompanion end
local function stat(a,k) return a:getStats():get(CharacterStat[k]) end
local function set(a,k,v) a:getStats():set(CharacterStat[k],v) end
local function shot(H,n) getCore():TakeFullScreenshot(H.config.run_id..'-camp-'..n..'.png') end
local function rows(w) local t={} for _,r in ipairs(w.rows or {}) do t[#t+1]=r.text end return table.concat(t,'\n') end
local function pcAt(cp)
 local sq=getCell():getGridSquare(cp.x,cp.y,cp.z)
 if sq then for i=0,sq:getObjects():size()-1 do local o=sq:getObjects():get(i) if S().Terminal.isComputer(o) then return o end end end
end
local function finish(H,f,t,phase)
 if S().Terminal.window then S().Terminal.window:close() end
 S().Config.debugPersona=nil
 H.player:setGhostMode(f.ghost)
 phase('finish',t)
end
local function logActors(f,t,result)
 for i,r in ipairs(f.crew) do
  local a=r.actor local d=S().Downtime.status(a) local c=S().Commands.peek(a) or {}
  print('SC_CAMP_RELEASE|actor_'..i..'|','name='..tostring(a:getFullName())..' hunger='..stat(a,'HUNGER')..' fatigue='..stat(a,'FATIGUE')..' endurance='..stat(a,'ENDURANCE')..' order='..tostring(c.order)..' action='..tostring(S().ActionSupervisor.current(a))..' downtime='..tostring(d and d.kind)..' phase='..tostring(d and d.phase)..' intent='..tostring((S().Decision.peek(a) or {}).intent)..' inside='..tostring(S().BaseLife.isInside(a))..' load='..a:getInventory():getCapacityWeight()..'/'..a:getMaxWeight()..' onbed='..tostring(a:isOnBed())..' xyz='..a:getX()..','..a:getY()..','..a:getZ())
 end
 f.lastLog=t
end
local function fixtures(H,f,check,result)
 local SC=S() local base=SC.BaseLife.active()
 for _,j in ipairs(base.jobs) do if j.state~='completed' and j.state~='cancelled' then SC.BaseLife.cancelJob(j.id) end end
 local zs=getCell():getZombieList() for i=zs:size()-1,0,-1 do local z=zs:get(i) z:removeFromWorld() z:removeFromSquare() end
 for i,r in ipairs(f.crew) do
  local a=r.actor SC.BaseWork.cancel(a,'camp_acceptance_fixture')
  SC.Commands.issue(r.id,'stay',nil,H.player)
  set(a,'HUNGER',.1) set(a,'THIRST',.1) set(a,'FATIGUE',.1) set(a,'ENDURANCE',.8)
 end
 local meal,sleeper,sorter,standing=f.crew[1],f.crew[2],f.crew[3],f.crew[4]
 f.meal,f.sleeper,f.sorter,f.standing=meal.actor,sleeper.actor,sorter.actor,standing.actor
 set(f.meal,'HUNGER',.72)
 f.food={} for i=1,12 do f.food[i]=f.meal:getInventory():AddItem('Base.Banana') end
 SC.BaseLife.assign(meal.id,'generalist',true) SC.Commands.issue(meal.id,'base_duty',nil,H.player)
 set(f.sleeper,'FATIGUE',.94) set(f.sleeper,'ENDURANCE',.3)
 SC.BaseLife.assign(sleeper.id,'generalist',true) SC.Commands.issue(sleeper.id,'base_duty',nil,H.player)
 set(f.standing,'ENDURANCE',.7) f.standStart=.7
 SC.BaseLife.assign(standing.id,'guard',false)
 local storage=SC.BaseLife.depositStorageRows('valuables')[1]
 f.container=storage and SC.BaseLife.resolveContainer(storage)
 check('camp_money_storage',f.container~=nil,'permitted Valuables storage from actual camp')
 if not f.container then return false end
 local source
 for radius=1,4 do for y=-radius,radius do for x=-radius,radius do
  local q=getCell():getGridSquare(storage.x+x,storage.y+y,storage.z)
  if not source and q and SC.GameplayUtil.isSquareFree(q) and SC.BaseLife.isInside(q,'area') then source=q end
 end end end
 if not check('camp_sort_source',source~=nil,'free floor near actual shelf') then return false end
 SC.BaseLife.beginZone('sorting_floor',source) local ok,zone=SC.BaseLife.finishZone(source,'sorting_floor')
 check('camp_sort_zone',ok==true,tostring(zone))
 if not ok then return false end
 f.money={} f.peak=0 f.storedAt=nil
 for i=1,20 do local item=f.sorter:getInventory():AddItem('Base.Money') f.money[i]=item
  assert(SC.GameplayUtil.dropItem(f.sorter:getInventory(),source,item,.45,.45,0))
 end
 SC.BaseLife.assign(sorter.id,'quartermaster',true) SC.Commands.issue(sorter.id,'base_duty',nil,H.player)
 local queued,job=SC.BaseLife.enqueueJob({type='sort_floor',priority=5,assignedId=sorter.id,target={zoneId=zone.id,x=source:getX(),y=source:getY(),z=source:getZ()}})
 check('camp_sort_job',queued==true,tostring(job and job.id)) f.job=job
 f.playerEndurance=stat(H.player,'ENDURANCE') f.fixtureAt=getTimestampMs() f.lastLog=0
 return true
end
function P.step(H,t,check,result,phase)
 local SC=S() local f=H.campAcceptance
 if H.phase=='persona_discovery_setup' then
  f=f or {ghost=H.player:isGhostMode(),crew={},gaps={},lastFrame=t} H.campAcceptance=f H.player:setGhostMode(true)
  f.crew={}
  if SC.UI then SC.UI.close() end
  if UIDebugConsole and UIDebugConsole.instance then UIDebugConsole.instance:setVisible(false) end
  if H.config.persona_discovery_resume=='true' then
   f.cp=ModData.get('LF_CampReleaseAcceptance')
   if not check('camp_resume_checkpoint',f.cp and f.cp.x~=nil,'saved follow-up and physical PC') then finish(H,f,t,phase) return end
   H.player:teleportTo(f.cp.x+.5,f.cp.y+.5,f.cp.z) phase('persona_discovery_camp_resume',t) return
  end
  for _,r in ipairs(SC.Registry.snapshot()) do if r.recruited and r.actor and not r.actor:isDead() and #f.crew<4 then f.crew[#f.crew+1]=r end end
  if #f.crew<4 and t-H.phaseStartedAt<20000 then return end
  if not check('camp_four_native_companions',#f.crew==4,'normal saved roster; decisions remain enabled') then finish(H,f,t,phase) return end
  check('camp_base_loaded',SC.BaseLife.active()~=nil,'existing native camp')
  f.lastFrame=t logActors(f,t,result)
  if H.config.camp_release_controlled=='true' then
   result('SKIP','camp_menus_closed_timing','recorded separately in SC-Harness-20261103-113323-a9d9c0b9; no repeated baseline')
   f.originalCrew=f.crew f.crew={}
   for _,r in ipairs(f.originalCrew) do SC.Actor.remove(r.actor) end
   f.spawnIndex=1 f.spawnAt={x=math.floor(H.player:getX()),y=math.floor(H.player:getY()),z=math.floor(H.player:getZ())}
   phase('persona_discovery_camp_spawn',t) return
  end
  phase('persona_discovery_camp_baseline',t) return
 elseif H.phase=='persona_discovery_camp_baseline' then
  f.gaps[#f.gaps+1]=t-f.lastFrame f.lastFrame=t
  if t-f.lastLog>=15000 then logActors(f,t,result) end
  if t-H.phaseStartedAt<90000 then return end
  table.sort(f.gaps) local n=#f.gaps
  result('PASS','camp_menus_closed_timing','90 seconds; samples='..n..' median_ms='..tostring(f.gaps[math.max(1,math.floor(n*.5))])..' p95_ms='..tostring(f.gaps[math.max(1,math.floor(n*.95))])..' max_ms='..tostring(f.gaps[n])..'; capped 30 FPS, isolated source build, no old-build comparison')
  shot(H,'baseline')
  f.originalCrew=f.crew f.crew={}
  for _,r in ipairs(f.originalCrew) do SC.Actor.remove(r.actor) end
  f.spawnIndex=1 f.spawnAt={x=math.floor(H.player:getX()),y=math.floor(H.player:getY()),z=math.floor(H.player:getZ())}
  phase('persona_discovery_camp_spawn',t) return
 elseif H.phase=='persona_discovery_camp_spawn' then
  if not f.ticket then
   local q=f.spawnAt local sq
   for radius=1,5 do for y=-radius,radius do for x=-radius,radius do
    local candidate=getCell():getGridSquare(q.x+x,q.y+y,q.z)
    local spaced=true
    for _,r in ipairs(f.crew) do if math.abs(r.actor:getX()-(q.x+x+.5))<2 and math.abs(r.actor:getY()-(q.y+y+.5))<2 then spaced=false break end end
    if not sq and spaced and candidate and SC.GameplayUtil.isSafeSpawnSquare(candidate) and SC.BaseLife.isInside(candidate,'area') then sq=candidate end
   end end end
   if not check('camp_fixture_free_tile_'..f.spawnIndex,sq~=nil,'free native camp floor') then finish(H,f,t,phase) return end
   local reason f.ticket,reason=SC.Actor.beginSpawn(sq,{recruited=true,identity={forename=({'Meal','Sleep','Sort','Rest'})[f.spawnIndex],surname='Tester',gender='woman',outfit='Generic01'}})
   if not check('camp_fixture_request_'..f.spawnIndex,f.ticket~=nil,tostring(reason)) then finish(H,f,t,phase) return end
   f.spawnStarted=t return
  end
  local actor,reason=SC.Actor.pollSpawn(f.ticket)
  if not actor and reason=='spawn_pending' and t-f.spawnStarted<20000 then return end
  if not check('camp_fixture_spawn_'..f.spawnIndex,actor~=nil,tostring(reason)) then finish(H,f,t,phase) return end
  f.crew[#f.crew+1]={actor=actor,id=SC.Registry.idOf(actor),recruited=true}
  f.ticket=nil f.spawnIndex=f.spawnIndex+1
  if f.spawnIndex<=4 then return end
  if not fixtures(H,f,check,result) then finish(H,f,t,phase) return end
  phase('persona_discovery_camp_behaviour',t) return
 elseif H.phase=='persona_discovery_camp_behaviour' then
  if t-f.lastLog>=15000 then logActors(f,t,result) end
  if not f.mealDone and stat(f.meal,'HUNGER')<.3 then f.mealDone=true result('PASS','camp_eat_below_30','native hunger='..stat(f.meal,'HUNGER')..' elapsed_ms='..(t-H.phaseStartedAt)) end
  if not f.standDone and not f.standing:isMoving() and f.standing:isSitOnGround()~=true and f.standing:isAsleep()~=true and stat(f.standing,'ENDURANCE')>f.standStart+.005 then f.standDone=true result('PASS','camp_standing_recovery','own endurance='..stat(f.standing,'ENDURANCE')..' initial='..f.standStart) end
  local sleeping=f.sleeper:isAsleep()==true or (SC.Commands.peek(f.sleeper) or {}).sleeping==true
  if sleeping and not f.sleepStart then f.sleepStart=stat(f.sleeper,'ENDURANCE') result('PASS','camp_natural_sleep','normal AI reached bed; endurance='..f.sleepStart) shot(H,'sleep') end
  if sleeping and f.sleepStart and not f.sleepDone and stat(f.sleeper,'ENDURANCE')>f.sleepStart+.005 then f.sleepDone=true result('PASS','camp_sleep_recovery','own endurance='..stat(f.sleeper,'ENDURANCE')..' at sleep='..f.sleepStart) end
  local carried,stored=0,0
  for _,item in ipairs(f.money) do local c=item:getContainer() if c==f.sorter:getInventory() then carried=carried+1 end if c==f.container then stored=stored+1 end end
  f.peak=math.max(f.peak,carried)
  if stored==20 then f.storedAt=f.storedAt or t elseif f.storedAt then f.sortLoop=true end
  f.sortDone=f.storedAt and t-f.storedAt>=15000 and not f.sortLoop
  local elapsed=t-H.phaseStartedAt
  if elapsed<300000 and not(f.mealDone and f.standDone and f.sleepDone and f.sortDone) then return end
  check('camp_meal_finished',f.mealDone==true,'hunger='..stat(f.meal,'HUNGER'))
  check('camp_standing_finished',f.standDone==true,'endurance='..stat(f.standing,'ENDURANCE'))
  check('camp_sleep_finished',f.sleepDone==true,'fatigue='..stat(f.sleeper,'FATIGUE'))
  check('camp_stack_carried',f.peak>1,'max simultaneous exact native cash receipts='..f.peak)
  check('camp_money_stable_storage',f.sortDone==true,'all 20 in same Valuables shelf for 15 seconds; stored='..stored..' loop='..tostring(f.sortLoop))
  check('camp_player_stamina_isolated',stat(H.player,'ENDURANCE')>=f.playerEndurance-.01,'player endurance='..stat(H.player,'ENDURANCE')..' before='..f.playerEndurance)
  f.scan={x=math.floor(H.player:getX())-32,y=math.floor(H.player:getY())-32,z=math.floor(H.player:getZ()),cursor=0}
  phase('persona_discovery_camp_pc',t) return
 elseif H.phase=='persona_discovery_camp_pc' then
  local q=f.scan for _=1,128 do if q.cursor>=4225 then break end local n=q.cursor q.cursor=n+1 local sq=getCell():getGridSquare(q.x+n%65,q.y+math.floor(n/65),q.z)
   if sq and SC.BaseLife.isInside(sq,'area') then for i=0,sq:getObjects():size()-1 do local o=sq:getObjects():get(i) if SC.Terminal.isComputer(o) then f.pc=o break end end end
   if f.pc then break end
  end
  if not f.pc and q.cursor<4225 then return end
  if not check('camp_native_pc',f.pc~=nil,'real computer inside actual camp') then finish(H,f,t,phase) return end
  getSandboxOptions():set('ElecShutModifier',2147483647) getSandboxOptions():toLua()
  local sq=f.pc:getSquare() H.player:teleportTo(sq:getX()+1.5,sq:getY()+.5,sq:getZ())
  SC.BaseWork.cancel(f.standing,'camp_reaction_fixture') SC.Commands.issue(f.crew[4].id,'stay',nil,H.player)
  f.standing:teleportTo(sq:getX()+1.5,sq:getY()+1.5,sq:getZ())
  local seed=1 while SC.TerminalSystem.random(seed+#'persona_spiffy'*71)(100)>35 do seed=seed+1 end
  local md=f.pc:getModData() md.movableData=md.movableData or {}
  SC.TerminalDrawers.release(f.pc) md.movableData.LF_LarchOS=SC.TerminalSystem.create(seed,'home',false,false,'camp-acceptance-persona') SC.Config.debugPersona='spiffy'
  assert(SC.Terminal.open(H.player,f.pc)) f.w=SC.Terminal.window
  phase('persona_discovery_camp_greeting',t) return
 elseif H.phase=='persona_discovery_camp_greeting' then
  if f.w.state~='idle' and t-H.phaseStartedAt<45000 then return end
  f.w:setEntryText('') for i=1,5 do f.w.entry.javaObject:putCharacter(('hello'):byte(i)) end
  f.w.entry.javaObject:onKeyEnter() phase('persona_discovery_camp_reply',t) return
 elseif H.phase=='persona_discovery_camp_reply' then
  if t-H.phaseStartedAt<1500 or f.w.state~='idle' and t-H.phaseStartedAt<45000 then return end
  local heard=false for _,r in ipairs(f.crew) do if SC.Dialogue.lastSpokenTopic(r.actor)=='terminal.lock.persona_spiffy' then heard=true result('PASS','camp_companion_persona_reaction','native speech actor='..r.actor:getFullName()) end end
  check('camp_persona_reaction_accepted',heard,'actual speech topic, normal availability/budget')
  check('camp_reaction_readable',rows(f.w):find(', nearby: ',1,true)~=nil,'accepted speech is visible above the full-screen CRT')
  shot(H,'companion-reaction') f.w:close() SC.Config.debugPersona=nil
  SC.TerminalDrawers.release(f.pc) local md=f.pc:getModData() md.movableData.LF_LarchOS=SC.TerminalSystem.create(33,'home',true,false,'camp-acceptance-emma')
  assert(SC.Terminal.open(H.player,f.pc)) f.w=SC.Terminal.window phase('persona_discovery_camp_followup',t) return
 elseif H.phase=='persona_discovery_camp_followup' or H.phase=='persona_discovery_camp_resume_ready' then
  if f.w.state~='idle' and t-H.phaseStartedAt<45000 then return end
  local text=rows(f.w) local line=SC.TerminalLocks.ledger().persona.campMentions.spiffy
  if H.config.persona_discovery_resume=='true' then
   check('camp_followup_once_after_reload',line and not text:find('where you picked that up',1,true),'saved receipt prevents replay in actual new process') shot(H,'followup-reload')
  else
   check('camp_followup_delivered',line and text:find('where you picked that up',1,true)~=nil,'completed real EMMA transcript marks once-only receipt') shot(H,'followup')
   local cp=ModData.getOrCreate('LF_CampReleaseAcceptance') cp.x,cp.y,cp.z=f.pc:getX(),f.pc:getY(),f.pc:getZ() cp.identity=f.w.system.identity
   check('camp_runtime_save',SC.Runtime.save()==true,'native LF persistence checkpoint before graceful game save')
  end
  finish(H,f,t,phase) return
 elseif H.phase=='persona_discovery_camp_resume' then
  f.pc=pcAt(f.cp) if not f.pc and t-H.phaseStartedAt<20000 then return end
  if not check('camp_same_pc_reloaded',f.pc and SC.Terminal.peekState(f.pc).identity==f.cp.identity,'same native physical computer identity') then finish(H,f,t,phase) return end
  assert(SC.Terminal.open(H.player,f.pc)) f.w=SC.Terminal.window phase('persona_discovery_camp_resume_ready',t) return
 end
end
return P
