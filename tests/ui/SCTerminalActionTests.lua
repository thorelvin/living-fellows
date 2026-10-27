-- SPDX-License-Identifier: MIT
-- Exercise real chat/menu confirmation, with domain commands replaced by spies.
local SC, T = SurvivorCompanion, TERMINAL_TEST
local Terminal, Actions, Brain = SC.Terminal, SC.TerminalActions, SC.TerminalBrain
local check, before = T.check, T.checks
local saved = { life = SC.BaseLife, vehicle = SC.Vehicle, refuel = SC.VehicleRefuel,
    generator = SC.GeneratorRefuel, medical = SC.Medical, registry = SC.Registry,
    expedition = SC.ExpeditionPrototype, taxi = SC.TaxiService, ui = SC.UI,
    now = SC.GameplayUtil.nowMs, valid = SC.GameplayUtil.isValidActor, name = SC.GameplayUtil.nameOf,
    nearest = SC.TerminalWorld.nearestGenerator, main = getSpecificPlayer, perks = Perks }
local player = T.player(101,100,0)
getSpecificPlayer = function(index) return index == 0 and player or nil end
SC.GameplayUtil.nowMs = function() return T.now end
SC.GameplayUtil.isValidActor = function(actor) return actor and not actor.dead end
SC.GameplayUtil.nameOf = function(actor) return actor.name end
SC.ExpeditionPrototype, SC.TaxiService = { isMember = function(actor) return actor.away == true end },
    { isDriver = function() return false end }
SC.UI = nil
Perks = { Doctor = "Doctor" }
local base, inside, calls, available = { id = "home", jobs = {} }, true, 0, true
local generator = {}
SC.TerminalWorld.nearestGenerator = function() return generator end
SC.BaseLife = {
    active = function() return base end,
    isInside = function() return inside end,
    job = function(id) for _, job in ipairs(base.jobs) do if job.id == id then return job end end end,
    retryJob = function(id) calls = calls + 1 return true, SC.BaseLife.job(id) end,
}
SC.GeneratorRefuel = {
    eligible = function() return available, "generator_full" end,
    queue = function(target, manual)
        check(target == generator and manual, "confirmed generator uses the checked manual queue")
        calls = calls + 1 return available, "base_gasoline_missing"
    end,
}
local car = { getScript = function() return { getName = function() return "Pickup" end } end }
SC.Vehicle = { loadedVehicles = function() return {car} end }
SC.VehicleRefuel = {
    eligible = function(actor) return actor == car and available, {id=42} end,
    queue = function(id, manual) check(id == 42 and manual, "confirmed car uses exact SQL identity") calls=calls+1 return true end,
}
local function open()
    local computer = T.computer(T.square(100,100,0,true))
    check(Terminal.open(player,computer), "action fixture opens")
    local window = Terminal.window
    window:flush()
    return window, computer
end
local function send(window, text)
    window:setFocusMode("chat") window.entry:setText(text) window:submit() window:flush()
end
local function text(window)
    local rows = {} for _, row in ipairs(window.rows) do rows[#rows+1] = row.text end
    return table.concat(rows,"\n")
end
local window, computer = open()
send(window,"can you refuel the generator")
check(window.requestTicket and calls == 0 and text(window):find("[Y/N]",1,true), "proposal is visible and has no queue effects")
send(window,"no")
check(not window.requestTicket and calls == 0, "no cancels without effects")
send(window,"refuel generator") send(window,"weather") send(window,"yes")
check(calls == 0, "another question cancels consent; later yes cannot dispatch it")
send(window,"refuel generator")
local consumed = window.requestTicket
send(window,"y")
check(calls == 1 and not window.requestTicket, "one yes submits one request")
check(Actions.execute(window,consumed) == false and calls == 1, "consumed ticket cannot replay")
send(window,"refuel generator") available=false send(window,"yes") available=true
check(calls == 2 and text(window):gsub("%s+"," "):find("base gasoline missing",1,true),
    "queue revalidates changed fuel supplies and reports failure across wrapped lines")
send(window,"refuel generator")
T.now=T.now+Actions.TTL_MS+1 send(window,"yes")
check(calls == 2 and text(window):find("expired",1,true), "old confirmations expire without dispatch")
send(window,"refuel generator") inside=false send(window,"yes") inside=true
check(calls == 2, "computer outside camp cannot execute an old confirmation")
send(window,"refuel generator")
local originalBase=base base={id="replacement",jobs={}} send(window,"yes") base=originalBase
check(calls == 2, "replacement camp cannot inherit a confirmation")
send(window,"refuel generator") window.system.locked=true
check(Actions.execute(window,window.requestTicket)==false and calls==2,"locking access invalidates a confirmation")
window.system.locked=false window:cancelRequest()
send(window,"refuel generator")
computer.data.movableData[SC.TerminalSystem.MEMORY_KEY]={locked=false}
check(Actions.execute(window,window.requestTicket)==false and calls==2,"replaced computer state cannot inherit consent")
computer.data.movableData[SC.TerminalSystem.MEMORY_KEY]=window.system window:cancelRequest()
send(window,"refuel generator") computer.square.generatorPower=false
window:watch(T.now+Terminal.WATCH_MS+1)
check(not window.requestTicket and window.state=="closing" and calls==2,"power loss cancels consent immediately")
window:close()

window,computer=open()
send(window,"refuel car") send(window,"yes")
check(calls==3,"car request enters existing job queue after confirmation")
send(window,"refuel pickup")
car={} send(window,"yes")
check(calls==3,"stale car reference is refused even when its number could be reused")
local job={id="job-1",type="gather_materials",state="blocked"} base.jobs={job}
send(window,"retry job job-1") send(window,"yes")
check(calls==4,"retry uses public job retry API")
send(window,"retry job job-1") base.jobs={{id="job-1",type=job.type,state="blocked"}} send(window,"yes")
check(calls==4,"reused job ID cannot redirect the confirmed operation")
base.jobs={job,{id="job-2",type="gather_materials",state="blocked"}}
send(window,"retry blocked jobs")
check(not window.requestTicket and text(window):find("Please name one target",1,true),"ambiguous jobs require a named choice")

local kate={name="Kate",hurt=true}
local alice={name="Alice",level=7}
local bob={name="Bob",level=2}
local expectedMedic=alice
function alice:getPerkLevel() return self.level end
function bob:getPerkLevel() return self.level end
local records={kate={id="kate",actor=kate,recruited=true,runtime={}},
    alice={id="alice",actor=alice,recruited=true,runtime={}}, bob={id="bob",actor=bob,recruited=true,runtime={}}}
SC.Registry={ living=function() return {kate,bob,alice} end, byId=function(id) return records[id] end,
    idOf=function(actor) for id,row in pairs(records) do if row.actor==actor then return id end end end }
SC.Medical={ assess=function(actor) return {hurt=actor.hurt} end,
    hasActionableNeed=function(_,assessment) return assessment.hurt==true end,
    peek=function(helper) return helper.treatment end,
    travelRescueEligible=function() return available end,
    canTreatPatient=function() return available end,
    treat=function(helper,patient,runtime)
        check(helper==expectedMedic and patient==kate and runtime==records[helper.name:lower()].runtime,"selected medic uses native checked treatment path and actual runtime")
        calls=calls+1 return true
    end }
send(window,"send medic to Kate")
check(window.requestTicket and text(window):find("Alice to check Kate",1,true) and calls==4,"proposal identifies patient and skilled helper")
send(window,"yes") check(calls==5,"medical proposal starts care once")
send(window,"ask the medic to check Kate") alice.away=true send(window,"yes") alice.away=false
check(calls==5,"departed expedition medic cannot be remotely redirected")
send(window,"send medic to Kate") available=false send(window,"yes") available=true
check(calls==5,"changed treatment readiness refuses care")
send(window,"send medic to Kate")
records.kate.actor={name="Kate",hurt=true} send(window,"yes") records.kate.actor=kate
check(calls==5,"a respawned patient needs a fresh confirmation")
send(window,"refuel generator")
local closedTicket=window.requestTicket window:close()
window=open() send(window,"yes")
check(calls==5 and Actions.execute(window,closedTicket)==false,"new sessions cannot inherit consent")

local previousQueue=SC.GeneratorRefuel.queue
SC.GeneratorRefuel.queue=function() calls=calls+1 error("simulated queue exception") end
send(window,"refuel generator") send(window,"yes") send(window,"yes")
check(calls==6 and not window.requestTicket,"throwing callback consumes consent and cannot repeat side effects")
SC.GeneratorRefuel.queue=previousQueue
send(window,"refuel generator")
local nestedTicket=window.requestTicket
SC.GeneratorRefuel.queue=function()
    check(Actions.execute(window,nestedTicket)==false,"nested callback cannot consume the same ticket twice")
    calls=calls+1 return true
end
send(window,"yes") check(calls==7,"nested callback submits exactly once")
SC.GeneratorRefuel.queue=previousQueue
inside=false send(window,"refuel generator") inside=true
check(not window.requestTicket and calls==7,"outside-camp requests cannot create tickets")
window:close()

-- Questions remain read-only; only a fixed set of explicit verbs can propose.
local world=SC.TerminalWorld.new(player,computer)
for _,question in ipairs({"who is hurt","power","why is work blocked","how much fuel","yes"}) do
    check(not Brain.respond(Brain.newSession({random=function() return 1 end}),question,world).proposal,"read-only question cannot propose an action: "..question)
end

-- Readiness for Kate does not imply that a medic is free: treat() continues
-- the helper's existing patient. Keep that ownership bound to the proposal.
window=open()
local beforeMedic=calls
alice.treatment={patient=bob}
expectedMedic=bob
send(window,"send medic to Kate")
check(window.requestTicket and text(window):find("Bob to check Kate",1,true) and calls==beforeMedic,
    "an idle medic is selected instead of a more skilled medic treating someone else")
send(window,"yes")
check(calls==beforeMedic+1,"the selected idle medic treats the confirmed patient")
bob.treatment={patient=alice}
send(window,"send medic to Kate")
check(not window.requestTicket and calls==beforeMedic+1 and text(window):find("No available camp medic",1,true),
    "no proposal is created when all medics own other patients")
alice.treatment=nil expectedMedic=alice
send(window,"send medic to Kate")
local changedPatientTicket=window.requestTicket
check(changedPatientTicket~=nil,"an available medic can be proposed again")
alice.treatment={patient=bob}
send(window,"yes")
check(calls==beforeMedic+1 and not window.requestTicket
    and Actions.execute(window,changedPatientTicket)==false,
    "taking another patient after the proposal refuses and consumes its confirmation")
alice.treatment={patient=kate}
send(window,"send medic to Kate") send(window,"yes")
check(calls==beforeMedic+2,"care already targeting the confirmed patient remains eligible")
alice.treatment,bob.treatment=nil,nil
local savedPeek=SC.Medical.peek
SC.Medical.peek=nil
send(window,"send medic to Kate")
check(not window.requestTicket and calls==beforeMedic+2,
    "unavailable treatment ownership cannot be assumed idle")
SC.Medical.peek=savedPeek
window:close()
Actions.reset()
SC.BaseLife,SC.Vehicle,SC.VehicleRefuel,SC.GeneratorRefuel=saved.life,saved.vehicle,saved.refuel,saved.generator
SC.Medical,SC.Registry,SC.ExpeditionPrototype,SC.TaxiService,SC.UI=saved.medical,saved.registry,saved.expedition,saved.taxi,saved.ui
SC.GameplayUtil.nowMs,SC.GameplayUtil.isValidActor,SC.GameplayUtil.nameOf=saved.now,saved.valid,saved.name
SC.TerminalWorld.nearestGenerator,getSpecificPlayer,Perks=saved.nearest,saved.main,saved.perks
SC_TEST_REPORT=SC_TEST_REPORT.."; Confirmed camp requests: "..(T.checks-before).." checks passed"
