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

    -- Every setter after the health deduction is checked. Previously only
    -- SetHealth was: a failing wound setter left the part damaged with no wound,
    -- no bleeding and no bite flag, and the function still reported success.
    -- Neither caller retries on false, so the health loss is never applied twice.
    local partial = nil
    local function apply(method, ...)
        local _, ok, err = U().call(part, method, ...)
        if ok ~= true and partial == nil then
            partial = method .. ":" .. tostring(err)
        end
        return ok == true
    end

    apply("setBleeding", true)
    if kind == "bite" then
        apply("SetBitten", true)
    elseif kind == "laceration" then
        -- setCut is the engine's laceration operation, and setCut(true) delegates
        -- to setCut(true, true) which never rolls infection. setDeepWounded(true)
        -- was silently upgrading every laceration into a deep wound, a different
        -- and far more serious injury than the one being rolled.
        apply("setCut", true)
    else
        -- BodyPart.setScratched(scratched, forceNoInfection). Verified from the
        -- 42.20.4 bytecode: when the second argument is FALSE the engine calls
        -- generateZombieInfection(7), a 7% Knox roll gated by sandbox
        -- transmission. Passing false therefore infected companions from
        -- scratches, contradicting this module's stated bites-only policy. The
        -- old comment called this argument a "weapon" flag; it is not.
        apply("setScratched", true, true)
    end

    -- Deliberately NOT clearing setWoundInfectionLevel. Resetting it to 0 erased
    -- a pre-existing infected wound as a side effect of an unrelated new scratch.

    if partial ~= nil then return false, "partial:" .. partial end
    return true, kind
end

-- Has this zombie's visible attack animation reached its impact phase? Entering
-- AttackState is too early: its first half-second is a grace pose with arms held
-- out. Damage at state entry looked like an invisible bite. Build 42 changes the
-- outcome to "success" from the animation's SetAttackOutcome event, and records
-- whether the native collision already wrote damage.
-- CB-04/CB-05. Build 42.20.4's zombie attack has a real episode lifecycle, and
-- reading it is what lets one swing produce exactly one result:
--
--   AttackState.enter()  attackOutcome = "start"; clears AttackDidDamage and
--                        ZombieBiteDone                      <- episode begins
--   animEvent            SetAttackOutcome -> "success" or "fail"
--   Zombie_Bite_Success  AttackCollisionCheck at 20% of the clip; the handler
--                        resolves the victim from zombie.target (NOT from the
--                        local players[] array), calls
--                        BodyDamage.AddRandomDamageFromZombie on it and writes
--                        the result into the AttackDidDamage variable
--   clip end             ZombieBiteDone = true
--   AttackState.exit()   clears AttackOutcome/AttackType/PlayerHitReaction
--
-- Two consequences drive the code below.
--
-- First, the engine's damage path *does* reach a detached companion: it looks
-- the victim up through the zombie's own target. So AttackDidDamage being
-- present at all is a receipt that victim processing ran, and its value is the
-- verdict. "Processed, no injury" is a real protected/defended outcome and must
-- be terminal -- re-wounding there would invent damage the engine declined.
--
-- Second, "start" is written by the engine at the top of every episode. That
-- is a true episode boundary, unlike the old rising edge of a sampled
-- predicate over target, distance and outcome: a momentary target or range
-- flicker used to reopen a resolved swing and let the same episode wound twice.
local function attackEpisodeFacts(zombie, actor)
    local facts = { eligible = false }
    if U().isZombie(zombie) ~= true or U().isDead(zombie) == true then return facts end
    facts.outcome = tostring(select(1, U().call(zombie, "getAttackOutcome")) or "")
    -- Presence, not truth: the variable is cleared on episode entry and written
    -- only by the collision handler, so a non-empty value is the receipt that
    -- victim processing actually ran.
    local damageVariable = select(1, U().call(zombie, "getVariableString", "AttackDidDamage"))
    facts.processed = type(damageVariable) == "string" and damageVariable ~= ""
    facts.damaged = select(1, U().call(zombie, "getAttackDidDamage")) == true
        or damageVariable == "true"
    facts.clipDone = select(1, U().call(zombie, "getVariableBoolean", "ZombieBiteDone")) == true

    if select(1, U().call(zombie, "getTarget")) ~= actor then return facts end
    local distance = U().distance(zombie, actor)
    if distance == math.huge then return facts end
    if distance > config("zombieAttackHoldRadius", 3.0) then return facts end
    local stateName = tostring(select(1, U().call(zombie, "getCurrentState")))
    local attacking = stateName:find("AttackState") ~= nil
        or select(1, U().call(zombie, "isZombieAttacking", actor)) == true
    if not attacking then return facts end
    facts.eligible = true
    return facts
end

-- Retained for callers and tests that only ask "is this zombie mid-swing at me
-- with a successful outcome"; the episode bookkeeping above is what resolve
-- actually uses.
local function isLandingAttack(zombie, actor)
    local facts = attackEpisodeFacts(zombie, actor)
    if not facts.eligible or facts.outcome ~= "success" then return false end
    return true, facts.damaged
end

-- One decision per episode. Returns the terminal receipt and whether the mod
-- should apply its own fallback wound, or nil while the episode is still in
-- flight and nothing can honestly be concluded yet.
local function episodeReceipt(swing, facts, current)
    if facts.outcome == "fail" then return "attack_failed", false end
    if facts.outcome ~= "success" then return nil, false end
    if facts.processed then
        -- The engine found this companion and decided. Either way it is done.
        return facts.damaged and "native_injury" or "processed_without_injury", false
    end
    if facts.clipDone then
        -- The clip ran to its end and the collision handler never wrote a
        -- verdict, so one of its own guards refused (no teeth, blocked line of
        -- sight, out of its tighter range). The swing visibly landed and
        -- nothing came of it: this is the case the fallback exists for.
        return "processing_omitted", true
    end
    local since = tonumber(swing.successAt)
    if since ~= nil and current - since
        >= config("zombieAttackProcessingGraceMs", 900) then
        -- Neither a verdict nor a finished clip within the grace. Surface it as
        -- its own outcome rather than silently guessing either way.
        return "processing_unobserved", true
    end
    return nil, false
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

-- CB-01. IsoZombie.postUpdateInternal() ends with
-- `canSeeTarget = isTargetVisible()` and zeroes targetSeenTime alongside it.
-- isTargetVisible() cannot find a deliberately detached companion, so both are
-- cleared EVERY FRAME. Restoring them only from the budgeted decision lane
-- (decisionCriticalIntervalMs = 50 ms, capped actors per callback, a 2 ms frame
-- budget) leaves the attack graph seeing an invisible target for most frames
-- between services: it exits AttackState, the next service asks for entry
-- again, and the result is the repeated lunge/bite-start stutter.
--
-- IngameState.update() calls IsoWorld.update() before it fires Lua's OnTick, so
-- a refresh from the tick lands after postupdate and is read by the next
-- frame's graph update. The phase was already right; only the cadence was not.
--
-- This registry is the set of pairs a resolve pass has already validated. The
-- per-frame service walks only that set -- never the world, never the zombie
-- list -- so the frame cost is proportional to the number of companions
-- actually being attacked.
local engagedPairs = {}
local engagedCount = 0

local function forgetPair(zombie)
    if engagedPairs[zombie] == nil then return end
    engagedPairs[zombie] = nil
    engagedCount = engagedCount - 1
end

local function rememberPair(zombie, actor, current)
    local entry = engagedPairs[zombie]
    if entry == nil then
        if engagedCount >= config("zombieAttackSustainMaxPairs", 24) then return false end
        engagedCount = engagedCount + 1
        entry = {}
        engagedPairs[zombie] = entry
    end
    entry.actor = actor
    entry.expiresAt = current + config("zombieAttackSustainExpiryMs", 1500)
    return true
end

-- Maintenance only: never requests attack entry. Returns the bridge's verdict
-- so a pair that has stopped being eligible is dropped rather than retried
-- every frame for ever.
local function sustainPair(zombie, actor)
    local bridge = type(_G) == "table" and rawget(_G, "SCBridge") or nil
    if bridge == nil or not SC.Call or type(SC.Call.static) ~= "function" then
        return false, "bridge_unavailable"
    end
    local ok, result = SC.Call.static(bridge, "sustainZombieAttack", zombie, actor)
    if not ok then return false, "bridge_call_failed" end
    local reason = tostring(result or "sustain_rejected")
    return reason == "sustained", reason
end

-- Run once per frame from the runtime tick, outside the budgeted per-actor
-- lane. Bounded by the registry size and by each entry's own expiry.
function ZombieAttack.sustainPulse(current)
    current = tonumber(current) or (U() and U().nowMs()) or 0
    local sustained, dropped = 0, 0
    for zombie, entry in pairs(engagedPairs) do
        local actor = entry.actor
        if current >= (tonumber(entry.expiresAt) or 0) then
            forgetPair(zombie); dropped = dropped + 1
        elseif actor == nil or not eligible(actor) then
            forgetPair(zombie); dropped = dropped + 1
        else
            local held, reason = sustainPair(zombie, actor)
            if held then
                sustained = sustained + 1
            else
                entry.lastRefusal = reason
                -- A momentarily-out-of-range pair stays registered until its
                -- expiry; a structurally dead one goes at once.
                if reason == "invalid_zombie" or reason == "invalid_life_state"
                    or reason == "different_target" or reason == "unowned_companion"
                    or reason == "companion_in_vehicle" then
                    forgetPair(zombie); dropped = dropped + 1
                end
            end
        end
    end
    if SC.CombatTrace and type(SC.CombatTrace.pulse) == "function" then
        SC.CombatTrace.pulse(current, sustained, dropped, engagedCount)
    end
    return sustained, dropped, engagedCount
end

function ZombieAttack.engagedPairCount() return engagedCount end

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
    if attackAccepted or attackStarted then
        -- A validated live pair joins the per-frame maintenance set, so its
        -- visibility survives the frames between decision services.
        rememberPair(zombie, actor, current)
        if SC.CombatTrace and type(SC.CombatTrace.entry) == "function" then
            SC.CombatTrace.entry(zombie, actor, current, attackReason, attackStarted)
        end
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
local function resolveGrapple(actor, current, attackers, evidence)
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
            -- The kill must be confirmed before it is reported. The pcall result
            -- was discarded and "grab_killed" returned regardless, so a failed
            -- or unavailable endLife was indistinguishable from a completed
            -- death -- the caller saw a kill that never happened.
            if SC.Actor == nil or type(SC.Actor.endLife) ~= "function" then
                return "grab_kill_unavailable"
            end
            local invoked, result = pcall(SC.Actor.endLife, actor)
            if invoked ~= true then
                return "grab_kill_failed"
            end
            if result == false then
                return "grab_kill_refused"
            end
            -- endLife reported success; confirm the actor is actually dead
            -- rather than trusting the return value alone.
            if U().isDead(actor) ~= true then
                return "grab_kill_unconfirmed"
            end
            return "grab_killed"
        end
        -- CB-07. A thin pile frees the companion, so an empty candidate slice
        -- reads as a rescue. That is only true if the absence was actually
        -- observed: while the pin suspends the decision pass, a partial or
        -- stale scan can report nobody simply because nothing looked. Require a
        -- complete observation before believing the attackers are gone -- but
        -- bound it, because refusing to act on uncertainty forever would pin a
        -- companion indefinitely, which is worse than releasing one early.
        local established = type(evidence) ~= "table"
            or evidence.complete == true or evidence.observed == false
        if attackers < threshold and not established then
            grabbed.unestablishedSince = grabbed.unestablishedSince or current
            if current - grabbed.unestablishedSince
                < config("zombieGrabEvidenceGraceMs", 2500) then
                return "grab_evidence_incomplete"
            end
        elseif attackers >= threshold then
            grabbed.unestablishedSince = nil
        end
        -- RESCUE: thin the pile below the threshold (kill/pull off attackers) and
        -- the companion is freed -- alive, if bloodied. This is the whole point of
        -- the grace window: a downed companion is savable.
        if attackers < threshold then
            -- A freed companion gets a few seconds to stand and fight before
            -- the same pile can pull it down again; re-pinning at once was the
            -- long knock-down loop.
            releaseCompanion(actor)
            grabState[actor] = { pinned = false,
                immuneUntil = current + config("zombieGrabRecoverMs", 4000) }
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
        -- One struggle per interval, so the odds do not depend on how often
        -- the critical lane happens to service this actor.
        if held >= config("zombieGrabMinDurationMs", 1500)
            and current >= (grabbed.nextEscapeAt or 0) then
            grabbed.nextEscapeAt = current + config("zombieGrabEscapeIntervalMs", 1000)
            local escape = config("zombieGrabEscapeChance", 0.2) * (0.5 + grappleEffectiveness(actor))
            if randChance() < escape then
                grabBark(actor, "grab.escaped")
                releaseCompanion(actor)
                grabState[actor] = { pinned = false,
                    immuneUntil = current + config("zombieGrabRecoverMs", 4000) }
                return "grab_escaped"
            end
        end
        -- Bleeding injury while held (real consequence), but the killing blow is
        -- gated on the grace window above so the player always has time to react.
        -- The death drag-down pose belongs to the fatal moment only: playing it
        -- on a living companion every drag interval was the jerky hug.
        if current >= (grabbed.nextDragAt or 0) then
            grabbed.nextDragAt = current + config("zombieGrabDragIntervalMs", 900)
            applyWound(actor, rollWound(config("zombieGrabBiteChance", 0.5)))
        end
        -- Keep the companion down, but only put it back once the state machine
        -- has started to stand, and at most once per refresh window. Forcing
        -- the flag every tick fought the get-up animation frame by frame.
        if current >= (grabbed.pinRefreshAt or 0)
            and select(1, U().call(actor, "isKnockedDown")) ~= true then
            grabbed.pinRefreshAt = current + config("zombieGrabPinRefreshMs", 1000)
            U().call(actor, "setKnockedDown", true)
        end
        return "grabbed"
    end
    if attackers >= threshold and current >= (grabbed and grabbed.immuneUntil or 0) then
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
                if SC.Tales and type(SC.Tales.noteCloseCall) == "function" then
                    pcall(SC.Tales.noteCloseCall, actor, "grabbed", current)
                end
                return "grabbed_now"
            end
            grabState[actor] = { pinned = false, lastAttemptAt = current }
        end
    end
    return "no_grab"
end

-- True while a zombie grab holds the companion down; the runtime skips its
-- decision so it cannot move or fight until freed.
--[[
CB-03. Build 42.20.4 has a real paired-grapple lifecycle: IsoGameCharacter
implements IGrappleableWrapper, and isBeingGrappled / getGrappledBy /
getGrappledByType / isPerformingGrappleGrabAnimation all resolve by reflection
on a companion, with IsoZombie grapple-capable on the other side. Verified
against the pinned JAR, not assumed from a method name.

The mod's own crowd pin is a separate, synthetic mechanism: a probability roll
that sets knockdown flags and writes wounds on a timer. It is NOT a native
grapple and must never be reported as one. Where the engine owns a real pair,
the engine owns the damage too -- running both at once would bite the companion
twice for one hold.

Returns nil when no native pair is held, otherwise a small descriptor.
]]
function ZombieAttack.nativeGrapple(actor)
    if actor == nil then return nil end
    local ok, held = pcall(function()
        return select(1, U().call(actor, "isBeingGrappled")) == true
    end)
    if not ok or held ~= true then return nil end
    local by = select(1, U().call(actor, "getGrappledBy"))
    local kind = select(1, U().call(actor, "getGrappledByType"))
    return {
        by = by,
        kind = type(kind) == "string" and kind or nil,
        grabbing = select(1, U().call(actor, "isPerformingGrappleGrabAnimation")) == true,
    }
end

-- True while the companion is held, by either authority. `source` tells them
-- apart so no caller can mistake the synthetic pin for a native grapple.
function ZombieAttack.isGrabbed(actor)
    if ZombieAttack.nativeGrapple(actor) ~= nil then return true, "native" end
    local g = grabState[actor]
    if type(g) == "table" and g.pinned == true then return true, "synthetic" end
    return false
end

-- Resolve incoming zombie attacks against one companion. `zombies` is the
-- already-bounded Senses threat list the runtime supplies; never rescan here.
function ZombieAttack.resolve(actor, current, zombies, evidence)
    if not eligible(actor) then return false, "invalid_actor" end
    if zombies == nil then return false, "zombie_candidates_unavailable" end
    current = tonumber(current) or (U() and U().nowMs()) or 0

    -- CB-03. When the engine owns a real paired grapple, it owns the damage,
    -- the pose and the release. The synthetic pin must not run alongside it:
    -- two authorities holding one victim meant timer wounds landing on top of
    -- native processing, and the pin's knockdown refresh fighting the engine's
    -- own get-up transitions. Stand down and let the native pair resolve.
    local native = ZombieAttack.nativeGrapple(actor)
    if native ~= nil then
        local held = grabState[actor]
        if type(held) == "table" and held.pinned == true then
            -- A native grapple started underneath our synthetic one. Drop ours
            -- rather than running both; the engine is now the authority.
            releaseCompanion(actor)
            grabState[actor] = nil
        end
        return true, "native_grapple", {
            checked = 0, applied = 0, landed = 0, pile = 0,
            targeting = 0, engagementAssists = 0,
            nativeGrapple = true, grappleKind = native.kind,
        }
    end

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
    local receipts = {}
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
            else
                -- The grace window exists for a lock that flickers off between
                -- perception scans, i.e. a zombie with NO current target. It
                -- previously counted on elapsed time alone, so a zombie that had
                -- switched to the player or another companion still counted
                -- toward this companion's pile for the whole grace period --
                -- exactly what the comment above says never happens. A live
                -- alternate victim invalidates our claim immediately.
                local existing = select(1, U().call(zombie, "getTarget"))
                local committedElsewhere = existing ~= nil and existing ~= actor
                    and U().isDead(existing) ~= true
                if committedElsewhere then
                    pileWindow[zombie] = nil
                elseif pileWindow[zombie] ~= nil
                    and current - pileWindow[zombie] <= grabGrace then
                    pile = pile + 1
                end
            end
        end
        local swing = swings[zombie]
        if not targetsMe then
            if swing then
                -- CB-05: losing the target for one pass is NOT an episode
                -- boundary. Clearing swing.resolved here is what let a momentary
                -- lock flicker reopen an already-resolved swing, so the same
                -- native episode could wound a second time once the reswing
                -- floor elapsed. Only AttackState.enter writing "start" ends an
                -- episode; the sighting bookkeeping below is separate.
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
            local assisted, attackStarted = false, false
            -- A pinned companion is already down: forcing fresh native swings
            -- on it kept the zombies locked in a lunge-and-hold over the body.
            -- The pin itself applies the drag wounds.
            if not ZombieAttack.isGrabbed(actor) then
                local _
                assisted, _, attackStarted = sustainNativeEngagement(
                    zombie, actor, swing, current, elapsed, targetDistance)
            end
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
        local facts = attackEpisodeFacts(zombie, actor)
        if not swing then swing = {} swings[zombie] = swing end

        -- The engine writes "start" at the top of every episode, so this is the
        -- episode boundary rather than a mod-sampled edge. Nothing else may
        -- reopen a resolved swing: that was the flicker defect.
        if facts.outcome == "start" and swing.outcome ~= "start" then
            swing.episode = (tonumber(swing.episode) or 0) + 1
            swing.resolved, swing.receipt = false, nil
            swing.successAt = nil
        end
        swing.outcome = facts.outcome

        -- `landed` stays a per-pass observation ("this zombie is mid-swing at
        -- me right now"); only the wound decision is once per episode.
        if facts.eligible and facts.outcome == "success" then
            swing.successAt = swing.successAt or current
            landed = landed + 1
        end

        if facts.eligible and swing.resolved ~= true then
            local receipt, wound = episodeReceipt(swing, facts, current)
            if receipt ~= nil then
                swing.resolved, swing.receipt, swing.at = true, receipt, current
                receipts[receipt] = (receipts[receipt] or 0) + 1
                if wound and applyWound(actor, rollWound(biteChance)) then
                    applied = applied + 1
                end
            end
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
    local grapple = resolveGrapple(actor, current, attackers, evidence)

    return true, applied > 0 and "companion_wounded" or "no_landed_attack",
        { checked = checked, targeting = targeting, landed = landed, applied = applied,
          pile = pile, attackers = attackers, grapple = grapple,
          engagementAssists = engagementAssists, nativeAttackStarts = nativeAttackStarts,
          targetReacquisitions = targetReacquisitions, receipts = receipts }
end

function ZombieAttack.reset(actor)
    if actor ~= nil then
        lastHitAt[actor] = nil
        -- Clear the native knockdown/drag-down flags along with the grab record,
        -- so a companion pulled from the pile by removal, recovery or teardown
        -- never keeps a pinned state that would skip its decisions.
        if grabState[actor] ~= nil then releaseCompanion(actor) end
        grabState[actor] = nil
        pileSeen[actor] = nil
        for zombie, entry in pairs(engagedPairs) do
            if entry.actor == actor then forgetPair(zombie) end
        end
    else
        lastHitAt = setmetatable({}, { __mode = "k" })
        grabState = setmetatable({}, { __mode = "k" })
        pileSeen = setmetatable({}, { __mode = "k" })
        engagedPairs, engagedCount = {}, 0
    end
    return true
end

SC.Modules = SC.Modules or {}
SC.Modules.zombieAttack = true
return ZombieAttack
