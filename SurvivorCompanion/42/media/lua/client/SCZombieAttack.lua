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
-- Per-companion, per-attacker timestamp of the last frame that zombie was seen
-- targeting this companion. Used to count the pull-down "pile" from zombies
-- committed to THIS companion while tolerating the brief target flicker between
-- perception scans -- a zombie locked onto the player or another NPC never
-- counts toward pulling this companion down.
local pileSeen = setmetatable({}, { __mode = "k" })

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
        -- Build 42 requires the second `weapon` flag. Calling the old one-argument
        -- shape throws from Kahlua after health loss, leaving attack resolution in
        -- a partially-applied state and spamming the console on subsequent swings.
        U().call(part, "setScratched", true, false)
        U().call(part, "setWoundInfectionLevel", 0.0)
    end
    return true, kind
end

-- Has this zombie's visible attack animation reached its impact phase? Entering
-- AttackState is too early: its first half-second is a grace pose with arms held
-- out. Damage at state entry looked like an invisible bite. Build 42 changes the
-- outcome to "success" from the animation's SetAttackOutcome event, and records
-- whether the native collision already wrote damage.
local function isLandingAttack(zombie, actor)
    if U().isZombie(zombie) ~= true or U().isDead(zombie) == true then return false end
    if select(1, U().call(zombie, "getTarget")) ~= actor then return false end
    local distance = U().distance(zombie, actor)
    if distance == math.huge then return false end
    if distance > config("zombieAttackHoldRadius", 3.0) then return false end
    local stateName = tostring(select(1, U().call(zombie, "getCurrentState")))
    local attacking = stateName:find("AttackState") ~= nil
        or select(1, U().call(zombie, "isZombieAttacking", actor)) == true
    if not attacking then return false end
    if tostring(select(1, U().call(zombie, "getAttackOutcome"))) ~= "success" then
        return false
    end
    return true, select(1, U().call(zombie, "getAttackDidDamage")) == true
end

-- `spotted()` selects a non-local companion, but Build 42's stock vision loop
-- only services entries in the local players[] array. The target can therefore
-- remain valid while the zombie sits in ZombieIdleState forever: bMoving is
-- never refreshed, so the animation graph never advances through lunge into
-- AttackState. Re-issue the ordinary native path-to-character intent after the
-- normal warning delay. This is deliberately not a movement or damage fallback;
-- Project Zomboid still owns pathfinding, facing, attack state, animation events,
-- collision, hit reaction, sound and the actual bite/grapple.
local function requestNativeAttack(zombie, actor)
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if bridge == nil or not SC.Call or type(SC.Call.static) ~= "function" then
        return false, "bridge_unavailable"
    end
    local ok, result = SC.Call.static(bridge, "startZombieAttack", zombie, actor)
    if not ok then return false, "bridge_call_failed", false end
    local reason = tostring(result or "attack_state_rejected")
    return reason == "attack_started" or reason == "attack_active",
        reason, reason == "attack_started"
end

local function sustainNativeEngagement(zombie, actor, swing, current, elapsed, distance)
    local delay = config("zombieAttackEngageAssistDelayMs", 500)
    if elapsed * 1000 < delay then return false, "warning_delay" end

    -- This bridge call is intentionally NOT throttled. IsoZombie.postupdate()
    -- clears canSeeTarget every frame for a companion outside players[], and the
    -- native attack graph exits AttackState on the next update if the adapter
    -- does not restore it. Java revalidates target, range, z and wall/door
    -- obstruction on every call before touching that visibility bit.
    local attackAccepted, attackReason, attackStarted =
        false, "outside_native_start_range", false
    if distance <= config("zombieAttackNativeStartRadius", 1.0) then
        attackAccepted, attackReason, attackStarted = requestNativeAttack(zombie, actor)
    end
    if attackStarted then return true, attackReason, true end
    if attackAccepted then return false, attackReason, false end

    local stateName = tostring(select(1, U().call(zombie, "getCurrentState")))
    if stateName:find("AttackState") ~= nil then return false, "attack_active", false end
    if current < (tonumber(swing.nextEngageAssistAt) or 0) then
        return false, attackReason == "outside_native_start_range"
            and "assist_cooldown" or attackReason, false
    end
    swing.nextEngageAssistAt = current
        + config("zombieAttackEngageAssistRetryMs", 750)
    local _, pathOk = U().call(zombie, "pathToCharacter", actor)
    if pathOk ~= true then return false, attackReason, false end
    return true, "native_path_refreshed:" .. attackReason, false
end

-- The same missing local-player visibility slot can make IsoZombie.postupdate()
-- drop a companion target between the 350 ms production targeting scans. Keep a
-- very short memory only after THIS zombie was observed targeting THIS actor,
-- and reacquire through the stock spotted() entry point. A living alternate
-- target is never stolen, and the forced close notice is refused across floors,
-- walls and closed doors.
local function restoreRecentCloseTarget(zombie, actor, current, lastTargetAt, distance, reach)
    if lastTargetAt == nil
        or current - lastTargetAt > config("zombieAttackTargetMemoryMs", 1200)
        or distance > reach then
        return false
    end
    local existing = select(1, U().call(zombie, "getTarget"))
    if existing ~= nil and U().isDead(existing) ~= true then return existing == actor end
    if not U().sameFloor(zombie, actor)
        or U().canSee(zombie, U().squareOf(actor)) ~= true then
        return false
    end
    local _, spotted = U().call(zombie, "spotted", actor, true)
    if spotted ~= true then return false end
    return select(1, U().call(zombie, "getTarget")) == actor
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

-- A grabbed companion cries out (and a pinned one being torn at is loud): the
-- bark sells the moment and, like combat chatter, makes a modest world sound so
-- nearby zombies can hear the struggle.
local function grabBark(actor, topic, lastWordsCircumstance)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return end
    local now = (U() and U().nowMs()) or 0
    local spoken
    if lastWordsCircumstance and type(SC.Dialogue.sayLastWords) == "function" then
        spoken = SC.Dialogue.sayLastWords(actor, lastWordsCircumstance)
    else
        spoken = SC.Dialogue.say(actor, topic, nil, nil,
            { recentLimit = 3, salt = tostring(now) })
    end
    if spoken ~= true then return end
    local x, y, z = U().position(actor)
    if x == nil then return end
    local radius = config("combatBarkSoundRadius", 8)
    if SC.Senses and type(SC.Senses.hear) == "function" then
        pcall(SC.Senses.hear, actor, x, y, z, radius, 10, "companion_grab_bark")
    end
    if type(addSound) == "function" then pcall(addSound, actor, x, y, z, radius, 10) end
end

-- Zombies pile onto and pull down an overwhelmed companion, just as they grab a
-- surrounded player. When enough are attacking it at once, roll (against the
-- companion's grapple traits) to grab and knock it to the ground; while pinned
-- it is torn at (drag-down damage) and cannot fight, and it is freed only when
-- the pile thins below the threshold or it struggles loose. If the drag-down
-- kills it, ordinary permadeath applies -- a swarmed companion can be lost.
local function resolveGrapple(actor, current, attackers)
    if select(1, U().call(actor, "getVehicle")) ~= nil then
        -- A seated companion can never be pinned. If it was grabbed and then
        -- boarded, clear the grab and its native knockdown/drag-down flags so the
        -- runtime does not skip its decisions for the rest of the ride.
        if grabState[actor] ~= nil then
            releaseCompanion(actor)
            grabState[actor] = nil
        end
        return "in_vehicle"
    end
    local grabbed = grabState[actor]
    local threshold = config("zombieGrabThreshold", 2)
    if grabbed and grabbed.pinned then
        -- Once the grace window has expired, the drag-down is fatal. Keep the
        -- living actor in the native death pose just long enough to own its
        -- final chat bubble; thinning the pile during this farewell cannot turn
        -- it into a false-alarm death speech.
        if grabbed.finalWordsAt ~= nil then
            if current - grabbed.finalWordsAt < config("lastWordsDeathDelayMs", 3000) then
                U().call(actor, "setDeathDragDown", true)
                U().call(actor, "setKnockedDown", true)
                return "grab_farewell"
            end
            releaseCompanion(actor); grabState[actor] = nil
            if SC.Actor and type(SC.Actor.endLife) == "function" then
                pcall(SC.Actor.endLife, actor)
            end
            return "grab_killed"
        end
        -- RESCUE: thin the pile below the threshold (kill/pull off attackers) and
        -- the companion is freed -- alive, if bloodied. This is the whole point of
        -- the grace window: a downed companion is savable.
        if attackers < threshold then
            releaseCompanion(actor); grabState[actor] = nil
            grabBark(actor, "grab.rescued"); return "grab_broken"
        end
        local held = current - (grabbed.pinnedAt or current)
        -- Grace expired while still pinned: the swarm drags it down for good.
        if held >= config("zombieGrabGraceMs", 9000) then
            -- Give the final line a living chat owner before permanent
            -- death cleanup removes the actor from the world.
            if SC.Dialogue and type(SC.Dialogue.sayLastWords) == "function" then
                SC.Dialogue.sayLastWords(actor, "zombies", nil, { force = true })
            end
            grabbed.finalWordsAt = current
            U().call(actor, "setDeathDragDown", true)
            U().call(actor, "setKnockedDown", true)
            return "grab_farewell"
        end
        -- SELF-ESCAPE: a tougher companion can struggle loose after a moment.
        if held >= config("zombieGrabMinDurationMs", 1500) then
            local escape = config("zombieGrabEscapeChance", 0.2) * (0.5 + grappleEffectiveness(actor))
            if randChance() < escape then
                grabBark(actor, "grab.escaped")
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
                -- Drop whatever it was doing; a pinned companion cannot act.
                if SC.Actor and type(SC.Actor.stop) == "function" then
                    pcall(SC.Actor.stop, actor)
                end
                grabState[actor] = { pinned = true, pinnedAt = current,
                    nextDragAt = current + 700 }
                grabBark(actor, nil, "pinned")
                return "grabbed_now"
            end
            grabState[actor] = { pinned = false, lastAttemptAt = current }
        end
    end
    return "no_grab"
end

-- True while a zombie grab holds the companion down; the runtime skips its
-- decision so it cannot move or fight until freed.
function ZombieAttack.isGrabbed(actor)
    local g = grabState[actor]
    return type(g) == "table" and g.pinned == true
end

-- Resolve incoming zombie attacks against one companion. `zombies` is the
-- already-bounded Senses threat list the runtime supplies; never rescan here.
function ZombieAttack.resolve(actor, current, zombies)
    if not eligible(actor) then return false, "invalid_actor" end
    if zombies == nil then return false, "zombie_candidates_unavailable" end
    current = tonumber(current) or (U() and U().nowMs()) or 0
    local reswingFloor = config("zombieAttackReswingMinMs", 300)
    local maximum = config("zombieAttackMaxChecks", 64)
    local biteChance = config("zombieBiteChance", 0.25)

    local swings = lastHitAt[actor]
    if not swings then
        swings = setmetatable({}, { __mode = "k" })
        lastHitAt[actor] = swings
    end
    local pileWindow = pileSeen[actor]
    if not pileWindow then
        pileWindow = setmetatable({}, { __mode = "k" })
        pileSeen[actor] = pileWindow
    end

    local holdRadius = config("zombieAttackHoldRadius", 3.0)
    local grabReach = config("zombieGrabReach", 1.6)
    local grabGrace = config("zombieGrabTargetGraceMs", 1200)
    local applied, checked, targeting, landed, pile, engagementAssists = 0, 0, 0, 0, 0, 0
    local nativeAttackStarts = 0
    local targetReacquisitions = 0
    U().each(zombies, maximum, function(zombie)
        checked = checked + 1
        if U().isZombie(zombie) ~= true or U().isDead(zombie) == true then return end
        local targetDistance = U().distance(zombie, actor)
        local targetsMe = select(1, U().call(zombie, "getTarget")) == actor
        if not targetsMe and restoreRecentCloseTarget(zombie, actor, current,
                pileWindow[zombie], targetDistance, grabReach) then
            targetsMe = true
            targetReacquisitions = targetReacquisitions + 1
        end
        -- The pull-down "pile": zombies in grab range committed to THIS companion.
        -- Count one targeting us now (and remember the frame), or one that targeted
        -- us within the grace window (its lock flickered off between perception
        -- scans). A zombie locked onto the player or another NPC never counts.
        if targetDistance <= grabReach then
            if targetsMe then
                pileWindow[zombie] = current
                pile = pile + 1
            elseif pileWindow[zombie] ~= nil
                and current - pileWindow[zombie] <= grabGrace then
                pile = pile + 1
            end
        end
        local swing = swings[zombie]
        if not targetsMe then
            if swing then
                swing.resolved = false
                swing.lastSightAt = nil
                swing.seenSince = nil
            end
            return
        end
        targeting = targeting + 1
        -- The stock vision loop only scans the local players[] array, so it never
        -- re-sees a detached companion. Worse, IsoZombie.update() resets native
        -- targetSeenTime to zero every frame because visibility slot 3 has no local
        -- camera. Accumulating from that native value therefore never crossed the
        -- attack animset's 0.5-second threshold: the zombie remained forever in
        -- Zombie_Idle_Lunge with its arms out. Track continuous same-target time
        -- ourselves and mirror that absolute duration back every tick. This keeps
        -- the vanilla half-second warning, then lets Zombie_Bite_Start/Success,
        -- AttackCollisionCheck and the victim reaction run normally.
        if targetDistance <= holdRadius then
            if not swing then swing = {} swings[zombie] = swing end
            if swing.seenSince == nil then swing.seenSince = current end
            local elapsed = math.max(0, current - swing.seenSince) / 1000
            local seen = number(zombie, "getTargetSeenTime") or 0
            U().call(zombie, "setTargetSeenTime", math.min(10, math.max(seen, elapsed)))
            local assisted, _, attackStarted = sustainNativeEngagement(
                zombie, actor, swing, current, elapsed, targetDistance)
            if assisted then engagementAssists = engagementAssists + 1 end
            if attackStarted then nativeAttackStarts = nativeAttackStarts + 1 end
            swing.lastSightAt = current
        elseif swing then
            swing.lastSightAt = nil
            swing.seenSince = nil
        end
        -- Edge-triggered wound application: one wound per swing episode.
        -- isLandingAttack is level-true for the whole time the zombie is mid-swing
        -- (and while its "success" outcome lingers afterwards), so a level check
        -- re-applied the same swing every frame -- bounded only by a time cooldown,
        -- which in turn swallowed a genuine fast second swing that arrived inside
        -- the window. Instead, resolve one wound on the rising edge into an attack
        -- and hold it until the zombie leaves the attack, so each distinct swing
        -- lands exactly once. A short reswing floor absorbs sub-swing state flicker
        -- without suppressing a real follow-up swing.
        local landing, nativeDamage = isLandingAttack(zombie, actor)
        if landing then
            landed = landed + 1
            if not swing then swing = {} swings[zombie] = swing end
            if swing.resolved ~= true
                and (swing.at == nil or current - swing.at >= reswingFloor) then
                swing.resolved = true
                swing.at = current
                -- The stock collision may now work for this IsoPlayer subtype. Do
                -- not double-wound it; retain the fallback only when the visible
                -- impact event succeeded without native body-damage application.
                if not nativeDamage and applyWound(actor, rollWound(biteChance)) then
                    applied = applied + 1
                end
            end
        elseif swing ~= nil then
            -- Episode closed: the zombie left the attack, so the next commit is a
            -- fresh swing that resolves its own wound.
            swing.resolved = false
        end
    end)

    -- Overwhelm pull-down: the crowd size (zombies in grab range targeting the
    -- companion) is the reliable count. getSurroundingAttackingZombies() reads 0
    -- for a non-local actor, so trust the pile.
    local attackers = pile
    local nativeValue = select(1, U().call(actor, "getSurroundingAttackingZombies"))
    local native = tonumber(nativeValue)
    if native and native > attackers then attackers = native end
    if (applied > 0 or landed > 0) and SC.Dialogue
        and type(SC.Dialogue.monitorMortality) == "function" then
        SC.Dialogue.monitorMortality(actor, nil, "zombie")
    end
    local grapple = resolveGrapple(actor, current, attackers)

    return true, applied > 0 and "companion_wounded" or "no_landed_attack",
        { checked = checked, targeting = targeting, landed = landed, applied = applied,
          pile = pile, attackers = attackers, grapple = grapple,
          engagementAssists = engagementAssists, nativeAttackStarts = nativeAttackStarts,
          targetReacquisitions = targetReacquisitions }
end

function ZombieAttack.reset(actor)
    if actor ~= nil then
        lastHitAt[actor] = nil
        -- Clear the native knockdown/drag-down flags along with the grab record,
        -- so a companion pulled from the pile by removal, recovery or teardown
        -- never keeps a pinned state that would skip its decisions.
        if grabState[actor] ~= nil then releaseCompanion(actor) end
        grabState[actor] = nil
    else
        lastHitAt = setmetatable({}, { __mode = "k" })
        grabState = setmetatable({}, { __mode = "k" })
    end
    return true
end

SC.Modules = SC.Modules or {}
SC.Modules.zombieAttack = true
return ZombieAttack
