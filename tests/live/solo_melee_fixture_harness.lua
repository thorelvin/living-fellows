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
SC_TEST_REPORT="SOLO_MELEE_FIXTURE_PASS checks=" .. checks
