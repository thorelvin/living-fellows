-- SPDX-License-Identifier: MIT

-- Applies the wound a zombie's attack should inflict on a companion.
--
-- Build 42 resolves a zombie swing (AttackState reaches "success" and sets
-- AttackDidDamage) and marks the victim via testDefense -- but the actual bite
-- or scratch is written by the victim's own local-player/animation-gated
-- processing, which never runs for a non-local companion. The engine therefore
-- reports the hit as landed while the companion's BodyDamage stays untouched, so
-- zombies visibly swarm a companion yet cannot hurt it. This module closes that
-- gap: when a real zombie is adjacent, locked onto the companion and attacking,
-- it applies the wound directly, bounded to one wound per attacker per cooldown.
--
-- Wound model (deliberate, single-player): bites carry the zombie infection and
-- can turn the companion; scratches and lacerations wound and bleed but never
-- infect. See [[sc-zombie-targeting]] for the lock that gets zombies here.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.ZombieAttack = SC.ZombieAttack or {}
local ZombieAttack = SC.ZombieAttack
-- Per-companion, per-attacker cooldown so one swing writes one wound.
local lastHitAt = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function config(key, fallback)
    local value = U() and U().config(key)
    if value == nil then return fallback end
    return value
end

local function eligible(actor)
    if not U() or U().isValidActor(actor) ~= true then return false end
    if U().isDead(actor) == true then return false end
    return true
end

-- One numeric return, guarded against the multi-value adapter return.
local function number(object, method, ...)
    if object == nil then return nil end
    local value = select(1, U().call(object, method, ...))
    return tonumber(value)
end

-- PZ's Kahlua VM exposes ZombRand, not math.random. Guard both so the
-- deterministic table fixture (neither present) still runs.
local function randInt(maxExclusive)
    maxExclusive = math.floor(tonumber(maxExclusive) or 0)
    if maxExclusive <= 1 then return 0 end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, maxExclusive)
        if ok and type(value) == "number" then return math.floor(value) % maxExclusive end
    end
    return 0
end

local function randChance()
    return randInt(1000) / 1000
end

-- Choose which of the zombie's melee outcomes a landed swing inflicts. Only a
-- true bite carries the zombie infection; scratches and lacerations wound and
-- bleed but never infect (deliberate: see the module header).
local function rollWound(biteChance)
    local roll = randChance()
    if roll < biteChance then return "bite" end
    -- Remaining swings split between a shallow scratch and a deeper laceration.
    if roll < biteChance + (1 - biteChance) * 0.5 then return "scratch" end
    return "laceration"
end

-- Write a single wound of the given kind to one body part, using the same native
-- BodyPart setters SCVitals captures and restores.
local function applyWound(actor, kind)
    local body = select(1, U().call(actor, "getBodyDamage"))
    if body == nil then return false, "no_body_damage" end
    local parts = select(1, U().call(body, "getBodyParts"))
    if parts == nil then return false, "no_parts_list" end
    -- Assign multi-returns to a local before tonumber: select() in argument
    -- position would forward U.call's ok flag as tonumber's base argument.
    local sizeValue = select(1, U().call(parts, "size"))
    local count = tonumber(sizeValue)
    if not count or count <= 0 then return false, "empty_parts:" .. tostring(count) end
    local part = select(1, U().call(parts, "get", randInt(count)))
    if part == nil then return false, "no_body_part" end

    local key = kind == "bite" and "zombieBiteDamage" or "zombieScratchDamage"
    local damage = config(key, kind == "bite" and 12 or 6)
    local health = number(part, "getHealth") or 100
    local _, healthOk, healthErr = U().call(part, "SetHealth", math.max(0.0, health - damage))
    if healthOk ~= true then return false, "SetHealth:" .. tostring(healthErr) end
    U().call(part, "setBleeding", true)
    if kind == "bite" then
        U().call(part, "SetBitten", true)
    elseif kind == "laceration" then
        U().call(part, "setDeepWounded", true)
        U().call(part, "setWoundInfectionLevel", 0.0)
    else
        U().call(part, "setScratched", true)
        U().call(part, "setWoundInfectionLevel", 0.0)
    end
    return true, kind
end

-- Is this zombie mid-attack on the companion right now? A zombie standing in its
-- AttackState/LungeState adjacent to its target is exactly the moment a regular
-- player takes the hit, so we key the wound to that (one per attacker per
-- cooldown). attackOutcome "success" and isZombieAttacking are looser fallbacks;
-- the swing lunge can carry the zombie a little past melee reach as it resolves,
-- so the completed-swing signal uses the wider hold radius.
local function isLandingAttack(zombie, actor)
    if U().isZombie(zombie) ~= true or U().isDead(zombie) == true then return false end
    if select(1, U().call(zombie, "getTarget")) ~= actor then return false end
    local distance = U().distance(zombie, actor)
    if distance == math.huge then return false end
    local reach = config("zombieAttackReach", 1.3)
    if distance <= reach then
        local state = tostring(select(1, U().call(zombie, "getCurrentState")))
        if state:find("AttackState") or state:find("LungeState") then return true end
        if select(1, U().call(zombie, "isZombieAttacking", actor)) == true then return true end
        if select(1, U().call(zombie, "isZombieAttacking")) == true then return true end
    end
    if distance <= config("zombieAttackHoldRadius", 3.0)
        and tostring(select(1, U().call(zombie, "getAttackOutcome"))) == "success" then
        return true
    end
    return false
end

-- Resolve incoming zombie attacks against one companion. `zombies` is the
-- already-bounded Senses threat list the runtime supplies; never rescan here.
function ZombieAttack.resolve(actor, current, zombies)
    if not eligible(actor) then return false, "invalid_actor" end
    if zombies == nil then return false, "zombie_candidates_unavailable" end
    current = tonumber(current) or (U() and U().nowMs()) or 0
    local cooldown = config("zombieAttackCooldownMs", 1600)
    local maximum = config("zombieAttackMaxChecks", 64)
    local biteChance = config("zombieBiteChance", 0.25)

    local cooldowns = lastHitAt[actor]
    if not cooldowns then
        cooldowns = setmetatable({}, { __mode = "k" })
        lastHitAt[actor] = cooldowns
    end

    local holdRadius = config("zombieAttackHoldRadius", 3.0)
    local applied, checked, targeting, landed = 0, 0, 0, 0
    U().each(zombies, maximum, function(zombie)
        checked = checked + 1
        if U().isZombie(zombie) ~= true or U().isDead(zombie) == true then return end
        if select(1, U().call(zombie, "getTarget")) ~= actor then return end
        targeting = targeting + 1
        -- The stock vision loop only scans the local players[] array, so it never
        -- re-sees a detached companion: the zombie's "seen flesh" timer runs past
        -- its memory and it drops the lock between targeting scans, lapsing out of
        -- the swing. Out-of-band spotted() would hold the lock but re-faces the
        -- zombie mid-swing and interrupts it. So we refresh only the two sight
        -- values continuous vision itself keeps -- exactly what "keep seeing this
        -- flesh" means -- without touching AI, damage or decisions.
        if U().distance(zombie, actor) <= holdRadius then
            pcall(function()
                zombie.timeSinceSeenFlesh = 0
                local floor = config("zombieTargetMemoryFrames", 200)
                if (tonumber(zombie.memory) or -1) < floor then zombie.memory = floor end
            end)
        end
        if not isLandingAttack(zombie, actor) then return end
        landed = landed + 1
        local last = tonumber(cooldowns[zombie]) or -math.huge
        if current - last < cooldown then return end
        cooldowns[zombie] = current
        if applyWound(actor, rollWound(biteChance)) then applied = applied + 1 end
    end)

    return true, applied > 0 and "companion_wounded" or "no_landed_attack",
        { checked = checked, targeting = targeting, landed = landed, applied = applied }
end

function ZombieAttack.reset(actor)
    if actor ~= nil then lastHitAt[actor] = nil
    else lastHitAt = setmetatable({}, { __mode = "k" }) end
    return true
end

SC.Modules = SC.Modules or {}
SC.Modules.zombieAttack = true
return ZombieAttack
