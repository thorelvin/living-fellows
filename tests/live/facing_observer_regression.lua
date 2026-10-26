-- SPDX-License-Identifier: MIT
local Probe = SCRealSandboxHarnessProbes.SCFacingProbe
local checks = 0
local function expect(value, why)
    checks = checks + 1
    assert(value, "facing observer " .. checks .. ": " .. why)
end
SurvivorCompanion = { Call = { resolve = function(actor, key)
    return actor ~= nil and type(actor[key]) == "function", actor and actor[key]
end } }
local x, y, fx, fy, angle, logical, model = 1, 0, 1, 0, 180, 0, true
local allocatingReads = 0
local actor = { getX = function() return x end, getY = function() return y end,
    getForwardDirectionX = function() return fx end, getForwardDirectionY = function() return fy end,
    getAnimAngle = function() return angle end, getDirectionAngle = function() return logical end,
    getAnimationPlayer = function() allocatingReads = allocatingReads + 1 return {} end,
    hasAnimationPlayer = function() return model end }
local previous = { x = 0, y = 0, at = 0 }
local frame = Probe.measure(actor, previous, 100)
expect(frame.forwardDot == 1 and frame.bodyDot < -0.999,
    "a correct logical direction cannot hide a reversed native body")
expect(frame.proven, "body/logical divergence proves native rotation through passive accessors")
x, fx, angle, logical = -1, -1, 180, 180
frame = Probe.measure(actor, previous, 100)
expect(frame.forwardDot == 1 and frame.bodyDot > 0.999, "westward travel and native degree angles use the same convention")
expect(not frame.proven, "fallback-only angles cannot prove a rendered model")
model = false
frame = Probe.measure(actor, previous, 100)
expect(frame.bodyDot == nil and not frame.proven, "missing models cannot produce a rendered-facing verdict")
model, x, fx, angle, logical = true, 1, 1, 90, 90
frame = Probe.measure(actor, previous, 100)
expect(math.abs(frame.bodyDot) < 0.0001, "a side step is perpendicular, not backward travel")
expect(Probe.measure(actor, { x = 1, y = 0, at = 0 }, 100).dx == nil,
    "stationary samples cannot supply directional evidence")
x = 0 / 0
expect(Probe.measure(actor, previous, 100).dx == nil, "invalid positions cannot supply directional evidence")
x, angle = 1, 0 / 0
expect(Probe.measure(actor, previous, 100).bodyDot == nil, "invalid native angles cannot silently pass")
expect(Probe.measure(actor, previous, 0).dx == nil, "nonadvancing time cannot supply directional evidence")
expect(allocatingReads == 0, "observation never calls the accessor that can allocate or rebind the model")
SC_TEST_REPORT = "FACING_OBSERVER_PASS checks=" .. checks
