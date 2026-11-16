-- SPDX-License-Identifier: MIT
-- Contract regression: moving-object removal cannot clear a native corpse's
-- static square entry. Require the native square API and verify the readback.
local probe=SCRealSandboxHarnessProbes.SCSoloMeleeProbe
local checks=0
local function check(value,message)
    checks=checks+1;assert(value,"solo melee fixture " .. checks .. ": " .. message)
end
local square={bodies={},calls=0}
local body={}
local entries={}
function entries:size() return #square.bodies end
function entries:get(index) return square.bodies[index+1] end
function square:getStaticMovingObjects() return entries end
function body:getSquare() return square end
function body:removeFromWorld() self.worldRemoved=true end
function body:removeFromSquare() self.movingRemoved=true end
function square:removeCorpse(target,remote)
    self.calls=self.calls+1
    check(target==body and remote==false,"native corpse removal keeps the local-square contract")
    self.bodies={}
end
square.bodies={body}
check(probe.removeBody(body)==true and square.calls==1 and #square.bodies==0,
    "the corpse leaves its static square list")
check(not body.worldRemoved and not body.movingRemoved,"generic moving-object calls are unnecessary")
square.bodies={body}
function square:removeCorpse() end
check(probe.removeBody(body)==false,"a no-op native call fails its readback")
function square:removeCorpse() error("native removal rejected") end
check(probe.removeBody(body)==false,"native failure cannot count as successful cleanup")
function square:removeCorpse() self.bodies={} end
function square:getStaticMovingObjects() return nil end
check(probe.removeBody(body)==false,"missing native readback cannot count as clean")
function body:getSquare() return nil end
check(probe.removeBody(body)==false,"a missing square is not a verified removal")
for _,expected in ipairs({{19,"Base.HandAxe",0},{24,"Base.HandAxe",5},
    {13,"Base.Axe",0},{25,"Base.WoodAxe",0},{61,"Base.Plank",0},
    {67,"Base.Sledgehammer",0},{73,"Base.Wrench",0},{84,"Base.KitchenKnife",5}}) do
    local weapon,count=probe.weaponForCase(expected[1])
    check(weapon and weapon[1]==expected[2] and count==expected[3],
        "extended requested weapons keep stable case mapping: " .. expected[1])
end
for _,index in ipairs({0,85,1.5}) do
    check(probe.weaponForCase(index)==nil,"invalid case cannot silently select a weapon: " .. index)
end
check(probe.trialTimeoutMs({})==90000,"default observation limit remains ninety seconds")
check(probe.trialTimeoutMs({solo_melee_trial_seconds="150"})==150000,
    "configured native observation limit preserves the longer measurement window")
check(probe.trialTimeoutMs({solo_melee_trial_seconds="bad"})==90000,
    "invalid observation limit falls back to the default")
check(probe.trialTimeoutMs({solo_melee_trial_seconds="1"})==30000,
    "short observation limits stay within the fixture bounds")
check(probe.trialTimeoutMs({solo_melee_trial_seconds="999"})==300000,
    "long observation limits stay bounded")
check(not probe.withdrawalComplete(1.1,10,40),
    "a brief retreat after long kiting cannot prematurely end the trial")
check(probe.withdrawalComplete(5.2,9,40),"a sustained native pull-out ends the trial")
check(not probe.withdrawalComplete(8,2,40),"a stationary failed escape is not a successful withdrawal")
check(not probe.withdrawalComplete(8,10,15),"spacing inside the field does not end the trial")
check(not probe.withdrawalComplete(0,0,40),"ending a retreat episode removes its withdrawal candidate")
local token=probe.receiptToken("test-run",82,1000,1)
check(type(token)=="string" and #token>0,"a zombie receipt is a durable unique value, not table identity")
check(token==string.sub(token,1),"serialized receipt values preserve zombie identity")
check(token~=probe.receiptToken("test-run",82,1000,2),"different zombies cannot share a receipt")
check(token~=probe.receiptToken("test-run",82,1001,1),"a repeated case gets fresh receipts")
check(token~=probe.receiptToken("other-run",82,1000,1),"fresh native clones cannot share a receipt")
SC_TEST_REPORT="SOLO_MELEE_FIXTURE_PASS checks=" .. checks
