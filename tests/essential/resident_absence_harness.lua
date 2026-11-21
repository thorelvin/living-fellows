-- SPDX-License-Identifier: MIT
-- Use the real restore queues, parked Handover transaction and vehicle storage.
local SC = SurvivorCompanion
local B, P = SC.BaseLife, SC.Persistence
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "resident absence " .. checks .. ": " .. message)
end
local function saved(id)
    return {id=id, recruited=true, identity={forename="Sam", surname="Clark", gender="female", outfit=""},
        position={x=200,y=100,z=0}, inventory={schema=2,complete=true,count=0,roots={},
            equipment={worn={},attached={}}}, skills={}, vitals={}, order={mode="follow"}}
end
local function keep(id, role, detail)
    B.forgetGoneResident(id)
    local row = B.resident(id)
    check(not SC.BaseWork.workerUnregistered(id) and row and row.role == role and row.duty == true, detail)
end
local okay, camp = B.create({x=11,y=12,z=0}, "Resident absence")
assert(okay)
local function add(id, role)
    assert(B.restoreResident(id, {present=true,value={baseId=camp.id,role=role,duty=true}}))
end

local waiting, invalid, passenger, dormant, parked, remote, dead =
    "sc-roster-waiting", "sc-roster-quarantine", "sc-roster-passenger", "sc-roster-dormant",
    "sc-roster-parked", "sc-roster-remote", "sc-roster-dead"
local roles = {[waiting]="medic", [invalid]="farmer", [passenger]="builder", [dormant]="guard",
    [parked]="angler", [remote]="chef", [dead]="maintainer"}
for id, role in pairs(roles) do add(id, role) end
check(P.restoreStatus() == false and not P.isPending(waiting), "the restore queue starts uninitialized")
keep(waiting, roles[waiting], "a restore in progress retains roster role and duty before the queue exists")

local payload = {schema=SC.Identity.saveSchema, baseLife=B.export(), companions={}}
local vehicle = saved(passenger)
vehicle.vehicle = {stored=true,seat=1,vehicle={id=123,script="Base.CarNormal"}}
payload.companions[passenger], payload.companions[waiting] = vehicle, saved(waiting)
payload.companions[invalid] = {id=invalid,recruited=true,identity="unreadable"}
payload.companions[remote] = saved(remote)
payload.companions[remote].restorePrimaryOnly = true
payload.companions[remote].inventory.preserveNativeIds = true
SC_TEST_SET_WORLD_STORE({document=payload})
assert(P.restore({}))
check(P.restoreStatus() and P.isPending(waiting) and not SC.Registry.byId(waiting),
    "an unloaded saved resident stays in the real spawn queue")
keep(waiting, roles[waiting], "unloaded squares preserve a pending resident")
check(P.pendingRestoreStatus(invalid) == "quarantined" and not P.isPending(invalid),
    "a raw invalid save is quarantined outside the spawn queue")
keep(invalid, roles[invalid], "a recoverable raw quarantine retains roster role and duty")
check(SC.Vehicle.contains(passenger) and not SC.Registry.byId(passenger) and not P.isPending(passenger),
    "accepted vehicle import transfers the owner's identity out of the spawn queue")
keep(passenger, roles[passenger], "a vehicle-stored passenger retains roster role and duty")
check(P.isPending(remote) and not SC.Registry.byId(remote), "remote primary-only restoration is pending")
keep(remote, roles[remote], "an unloaded expedition member retains roster role and duty")

local lookup = SC.Registry.byId
local records = {[dormant]={id=dormant,recruited=true,actor=nil}}
SC.Registry.byId = function(id) return records[id] or lookup(id) end
keep(dormant, roles[dormant], "a dormant registry record retains roster role and duty")

local player = {getX=function() return 0 end,getY=function() return 0 end,getZ=function() return 0 end}
local crew = {getX=function() return 200 end,getY=function() return 100 end,getZ=function() return 0 end}
records[parked] = {id=parked,actor=crew,recruited=true}
SC.Registry.idOf = function(actor) if actor == crew then return parked end end
SC.Handover = {KEY="roster-test-handover",isPaused=function() return false end,retired=function() return false end}
SC.Commands = {peek=function() return {order="follow",commandSerial=0} end}
local world = ModData.getOrCreate(SC.Handover.KEY)
world.crew = {[parked]={id=parked,serial=0,phase="sheltered",shelterReported=true,nextShelterAt=math.huge}}
local owner, removed = "handover", false
SC.ViewSession = {owner=function() return owner end,slotSqlId=function() return 2 end,
    released=function() owner=nil; return true end}
SCBridge = {pollHandoverPlayerAdmission=function() end}
SCSplitScreenProbe = {releaseHandoverView=function() return true end,flushGlobalModDataForWorldExit=function() return true end}
function getSpecificPlayer(index) if index == 0 then return player end end
P.captureRecord = function(record) return saved(record.id) end
P.save = function() return true end
SC.Actor = {remove=function(actor)
    assert(actor == crew and P.isPending(parked), "Handover retained the exact actor before removal")
    records[parked], removed = nil, true
    return true
end}
SC.HandoverRescue.pulse()
check(removed and owner == nil and not SC.Registry.byId(parked) and P.isPending(parked),
    "the production shelter pulse parked its companion in the restore queue")
keep(parked, roles[parked], "parked Handover crew retain roster role and duty")

check(B.forgetGoneResident(dead) and not B.resident(dead), "an unowned missing resident can be retired")
for i = 1, 16 do B.auditResidentRoster() end
for id, role in pairs(roles) do
    if id ~= dead then
        local row = B.resident(id)
        check(row and row.baseId == camp.id and row.role == role and row.duty,
            "bounded migration keeps the same duty and role for " .. id)
    end
end
SC_TEST_REPORT = "CAMP_RESIDENT_ABSENCE_PASS checks=" .. checks
