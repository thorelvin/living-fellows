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
-- Per-companion grab/pin state for the overwhelm pull-down.
local grabState = setmetatable({}, { __mode = "k" })

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

-- Knock the companion to the ground the way an overwhelming zombie grab does,
-- setting the same flags the engine's grab sequence sets on a victim so the
-- companion's own state machine plays the fall/on-ground animation.
local function knockCompanionDown(actor)
    U().call(actor, "setFallOnFront", randChance() < 0.5)
    U().call(actor, "setKnockedDown", true)
end

local function releaseCompanion(actor)
    U().call(actor, "setDeathDragDown", false)
    U().call(actor, "setKnockedDown", false)
end

-- Higher trait effectiveness = harder to grab, easier to break free.
local function grappleEffectiveness(actor)
    local value = select(1, U().call(actor, "calculateGrappleEffectivenessFromTraits"))
    local v = tonumber(value)
    if v == nil then return 0.5 end
    return v
end

-- Zombies pile onto and pull down an overwhelmed companion, just as they grab a
-- surrounded player. When enough are attacking it at once, roll (against the
-- companion's grapple traits) to grab and knock it to the ground; while pinned
-- it is torn at (drag-down damage) and cannot fight, and it is freed only when
-- the pile thins below the threshold or it struggles loose. If the drag-down
-- kills it, ordinary permadeath applies -- a swarmed companion can be lost.
local function resolveGrapple(actor, current, attackers)
    if select(1, U().call(actor, "getVehicle")) ~= nil then return "in_vehicle" end
    local grabbed = grabState[actor]
    local threshold = config("zombieGrabThreshold", 2)
    if grabbed and grabbed.pinned then
        -- RESCUE: thin the pile below the threshold (kill/pull off attackers) and
        -- the companion is freed -- alive, if bloodied. This is the whole point of
        -- the grace window: a downed companion is savable.
        if attackers < threshold then
            releaseCompanion(actor); grabState[actor] = nil; return "grab_broken"
        end
        local held = current - (grabbed.pinnedAt or current)
        -- Grace expired while still pinned: the swarm drags it down for good.
        if held >= config("zombieGrabGraceMs", 9000) then
            releaseCompanion(actor); grabState[actor] = nil
            if SC.Actor and type(SC.Actor.endLife) == "function" then
                pcall(SC.Actor.endLife, actor)
            end
            return "grab_killed"
        end
        -- SELF-ESCAPE: a tougher companion can struggle loose after a moment.
        if held >= config("zombieGrabMinDurationMs", 1500) then
            local escape = config("zombieGrabEscapeChance", 0.2) * (0.5 + grappleEffectiveness(actor))
            if randChance() < escape then
                releaseCompanion(actor); grabState[actor] = nil; return "grab_escaped"
            end
        end
        -- Bleeding injury while held (real consequence), but the killing blow is
        -- gated on the grace window above so the player always has time to react.
        if current >= (grabbed.nextDragAt or 0) then
            grabbed.nextDragAt = current + config("zombieGrabDragIntervalMs", 900)
            applyWound(actor, rollWound(config("zombieGrabBiteChance", 0.5)))
            U().call(actor, "setDeathDragDown", true)
        end
        -- Re-assert the pin each tick; the state machine would otherwise stand up.
        U().call(actor, "setKnockedDown", true)
        return "grabbed"
    end
    if attackers >= threshold then
        local lastAttempt = grabbed and grabbed.lastAttemptAt or -math.huge
        if current - lastAttempt >= config("zombieGrabAttemptCooldownMs", 1200) then
            local chance = config("zombieGrabChance", 0.3)
                * math.max(0.2, 1.5 - grappleEffectiveness(actor))
            if randChance() < chance then
                knockCompanionDown(actor)
                grabState[actor] = { pinned = true, pinnedAt = current,
                    nextDragAt = current + 700 }
                return "grabbed_now"
            end
            grabState[actor] = { pinned = false, lastAttemptAt = current }
        end
    end
    return "no_grab"
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
    local grabReach = config("zombieGrabReach", 1.6)
    local applied, checked, targeting, landed, pile = 0, 0, 0, 0, 0
    U().each(zombies, maximum, function(zombie)
        checked = checked + 1
        if U().isZombie(zombie) ~= true or U().isDead(zombie) == true then return end
        -- The "pile": zombies crowding the companion in grab range. Count them by
        -- proximity before the target gate -- a crowded-in zombie is part of the
        -- overwhelm even on the frames its target flickers off between scans.
        if U().distance(zombie, actor) <= grabReach then pile = pile + 1 end
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

    -- Overwhelm pull-down: the crowd size (zombies in grab range targeting the
    -- companion) is the reliable count. getSurroundingAttackingZombies() reads 0
    -- for a non-local actor, so trust the pile.
    local attackers = pile
    local nativeValue = select(1, U().call(actor, "getSurroundingAttackingZombies"))
    local native = tonumber(nativeValue)
    if native and native > attackers then attackers = native end
    local grapple = resolveGrapple(actor, current, attackers)

    return true, applied > 0 and "companion_wounded" or "no_landed_attack",
        { checked = checked, targeting = targeting, landed = landed, applied = applied,
          pile = pile, attackers = attackers, grapple = grapple }
end

function ZombieAttack.reset(actor)
    if actor ~= nil then lastHitAt[actor] = nil; grabState[actor] = nil
    else
        lastHitAt = setmetatable({}, { __mode = "k" })
        grabState = setmetatable({}, { __mode = "k" })
    end
    return true
end

SC.Modules = SC.Modules or {}
SC.Modules.zombieAttack = true
return ZombieAttack
