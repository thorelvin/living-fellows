-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then
    pcall(require, "SCGameplayUtil")
end

SC.ZombieFacts = SC.ZombieFacts or {}
local ZombieFacts = SC.ZombieFacts
local cachedFrame, entries = nil, {}
local ABSENT = { gone = true, zombie = false }

local function truthyCall(value, methodName, ...)
    local result, ok = SC.GameplayUtil.call(value, methodName, ...)
    return ok and result == true
end

local function compute(zombie)
    local utility = SC.GameplayUtil
    if not utility or not utility.isZombie(zombie) then
        return { gone = true, zombie = false }
    end
    if utility.isGoneTarget(zombie) then
        return { gone = true, zombie = true }
    end
    local x, y, z = utility.position(zombie)
    local square = utility.squareOf(zombie)
    local floor = square and select(3, utility.position(square)) or nil
    local crawling = truthyCall(zombie, "isCrawling")
        or truthyCall(zombie, "getVariableBoolean", "bCrawling")
    local onFloor = not crawling and
        (truthyCall(zombie, "isOnFloor") or truthyCall(zombie, "isProne"))
    local attacking = truthyCall(zombie, "isAttacking")
        or truthyCall(zombie, "isZombieAttacking")
        or truthyCall(zombie, "getVariableBoolean", "bAttack")
    local climbing = truthyCall(zombie, "isClimbing")
    if not attacking or not climbing then
        local state = select(1, utility.call(zombie, "getCurrentState"))
        local name = state ~= nil and string.lower(tostring(state)) or ""
        if not attacking then
            attacking = string.find(name, "attackstate", 1, true) ~= nil
        end
        if not climbing then
            climbing = string.find(name, "climbthroughwindow", 1, true) ~= nil
                or string.find(name, "climboverfence", 1, true) ~= nil
                or string.find(name, "climboverwall", 1, true) ~= nil
        end
    end
    return {
        zombie = true, gone = false, x = x, y = y, z = z,
        square = square, floor = floor,
        posture = crawling and "crawler" or onFloor and "downed" or "standing",
        attacking = attacking == true,
        climbing = climbing == true,
        target = select(1, utility.call(zombie, "getTarget")),
    }
end

function ZombieFacts.get(zombie)
    if zombie == nil then return ABSENT end
    local runtime = SC.Runtime
    local frame = runtime and type(runtime.frameSerial) == "function"
        and runtime.frameSerial() or nil
    if frame == nil then return compute(zombie) end
    if cachedFrame ~= frame then
        entries, cachedFrame = {}, frame
    end
    local entry = entries[zombie]
    if entry == nil then
        entry = compute(zombie)
        entries[zombie] = entry
        if SC.Performance and type(SC.Performance.count) == "function" then
            SC.Performance.count("zombie.facts.build")
        end
    elseif SC.Performance and type(SC.Performance.count) == "function" then
        SC.Performance.count("zombie.facts.hit")
    end
    return entry
end

function ZombieFacts.forget(zombie)
    if zombie ~= nil then entries[zombie] = nil end
end

function ZombieFacts.reset()
    entries, cachedFrame = {}, nil
end

return ZombieFacts
