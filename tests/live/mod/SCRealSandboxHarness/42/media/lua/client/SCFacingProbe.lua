-- SPDX-License-Identifier: MIT
-- Controlled ordinary locomotion; native animation angles are observed only.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance then
    require "SCBanditsCombatAcceptance"
end
local Probe = {}
local Shared = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.shared
local call = Shared.call
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
function Probe.measure(actor, previous, current)
    local x, y = actor:getX(), actor:getY()
    local frame = { x = x, y = y, at = current }
    if not previous or current <= previous.at then return frame end
    local dx, dy = x - previous.x, y - previous.y
    if not finite(dx) or not finite(dy) then return frame end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.02 then return frame end
    frame.dx, frame.dy = dx, dy
    local fx, fy = call(actor, "getForwardDirectionX"), call(actor, "getForwardDirectionY")
    if finite(fx) and finite(fy) then frame.forwardDot = (dx * fx + dy * fy) / length end
    frame.angle = call(actor, "getAnimAngle") -- Native degrees; not the rendered angle's +pi/2 model offset.
    frame.logical = call(actor, "getDirectionAngle")
    -- Never call getAnimationPlayer: that accessor can allocate/rebind a model.
    -- getAnimAngle is a passive read with a logical-angle fallback when the
    -- model is unready. A difference proves native body rotation was read;
    -- a fallback-only trace cannot pass a leg.
    frame.proven = call(actor, "hasAnimationPlayer") == true
        and finite(frame.angle) and finite(frame.logical)
        and math.cos(math.rad(frame.angle - frame.logical)) < 0.9999
    if call(actor, "hasAnimationPlayer") == true and finite(frame.angle) then
        frame.bodyDot = (dx * math.cos(math.rad(frame.angle)) + dy * math.sin(math.rad(frame.angle))) / length
    end
    return frame
end
local function observeSaved(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.facingSaved
    if not f then
        if current - H.startedAt < 8000 or not SC.State.active then return end
        H.facingSaved = { primary = Shared.playerState(), started = current, actors = {} }
        getGameTime():setTimeOfDay(12)
        return
    end
    if current < (f.nextAt or 0) then return end
    f.nextAt = current + 100
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        local actor = record.actor
        if actor and SC.GameplayUtil.isValidActor(actor) and not actor:isDead() then
            local row = f.actors[record.id]
            if not row or row.actor ~= actor then row = { actor = actor, samples = 0, backward = 0 } f.actors[record.id] = row end
            local frame = Probe.measure(actor, row.previous, current)
            row.previous = frame
            if frame.dx then
                row.samples = row.samples + 1
                if frame.bodyDot and frame.bodyDot < -0.5 then row.backward = row.backward + 1 end
                local decision = SC.Decision.peek(actor) or {}
                print("SC_FACING_OBSERVE|id=" .. record.id .. "|point=" .. frame.x .. "," .. frame.y
                    .. "|delta=" .. frame.dx .. "," .. frame.dy .. "|forward_dot=" .. tostring(frame.forwardDot)
                    .. "|body_dot=" .. tostring(frame.bodyDot) .. "|angle=" .. tostring(frame.angle)
                    .. "|logical=" .. tostring(frame.logical) .. "|body_proven=" .. tostring(frame.proven)
                    .. "|backward_anim=" .. tostring(call(actor, "isAnimatingBackwards"))
                    .. "|dragging=" .. tostring(call(actor, "isCompanionCorpseDragActive"))
                    .. "|intent=" .. tostring(decision.intent))
                if current >= (f.pictureAt or 0) and frame.bodyDot and frame.bodyDot < -0.5 then
                    getCore():TakeFullScreenshot(H.config.run_id .. "-facing-saved-" .. math.floor((current - f.started) / 1000) .. ".png")
                    f.pictureAt = current + 2000
                end
            end
        end
    end
    if current - f.started >= 45000 then
        for id, row in pairs(f.actors) do print("SC_FACING_OBSERVE|SUMMARY|id=" .. id .. "|moving=" .. row.samples .. "|backward=" .. row.backward) end
        check("facing_observe_primary", Shared.samePlayers(f.primary), "native main identity and slots unchanged")
        result("PASS", "facing_observation_complete", "45 seconds; saved NPC orders untouched; daylight; observations are not a no-moonwalk verdict")
        H.facingSavedDone = true
        if H.config.companion_facing_mode ~= "both" then setPhase("finish", current) end
    end
end
local function finish(H, current, check, result, setPhase, good, why)
    local f = H.facing
    if f then
        good = check("facing_primary_ownership", Shared.samePlayers(f.primary), "main identity, slots and count unchanged") and good
        print("SC_FACING|SUMMARY|moving=" .. (f.samples or 0) .. "|rendered=" .. (f.rendered or 0)
            .. "|backward=" .. (f.backward or 0) .. "|longest_backward_ms=" .. (f.longestBackward or 0))
    end
    result(good and "PASS" or "FAIL", "companion_facing_probe", why)
    setPhase("finish", current)
end
local function order(SC, H, f, current)
    local target = f.leg == 1 and f.site.enemy or f.site.fellow
    local good, reason = SC.Commands.issue(f.id, "move_to", {
        x = target:getX(), y = target:getY(), z = target:getZ(),
    }, f.primary.player)
    f.target, f.legAt, f.previous, f.pictureAt = target, current, nil, current + 1500
    return good, reason
end
function Probe.step(H, current, check, result, setPhase)
    if H.config.companion_facing_mode == "saved"
        or H.config.companion_facing_mode == "both" and not H.facingSavedDone then
        return observeSaved(H, current, check, result, setPhase)
    end
    local SC, f = SurvivorCompanion, H.facing
    if not f then
        if current - H.startedAt < 8000 or not SC.State.active or SC.Registry.count() == 0 then return end
        local primary = Shared.playerState()
        local site = Shared.field(SC, primary.player)
        if not site then return finish(H, current, check, result, setPhase, false, "no clear native movement strip") end
        primary.player:teleportTo(site.observer:getX() + 0.5, site.observer:getY() + 0.5, site.observer:getZ())
        getGameTime():setTimeOfDay(12)
        local ticket, reason = SC.Actor.beginSpawn(site.fellow, {
            recruited = true, identity = SC.Spawn.generateIdentity(), background = { profession = "unemployed" },
        })
        if not ticket then return finish(H, current, check, result, setPhase, false, tostring(reason)) end
        H.facing = { ticket = ticket, primary = primary, site = site, started = current, leg = 1 }
        return
    end
    if not f.actor then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" then finish(H, current, check, result, setPhase, false, tostring(reason)) end
            return
        end
        f.actor, f.id = actor, SC.Registry.idOf(actor)
        for _, command in ipairs({ { "stay" }, { "set_scavenge", false }, { "set_move_mode", "walk" } }) do
            local good, why = SC.Commands.issue(f.id, command[1], command[2], f.primary.player)
            if not good then return finish(H, current, check, result, setPhase, false, tostring(why)) end
        end
        local good, why = order(SC, H, f, current)
        if not good then finish(H, current, check, result, setPhase, false, tostring(why)) end
        return
    end
    if f.actor:isDead() or f.primary.player:isDead() or current - f.started > 90000 then
        return finish(H, current, check, result, setPhase, false, "native death or movement deadline")
    end
    if current < (f.nextAt or 0) then return end
    f.nextAt = current + 100
    local frame = Probe.measure(f.actor, f.previous, current)
    f.previous = frame
    if frame.dx then
        f.legEvidence = f.legEvidence or {}
        local evidence = f.legEvidence[f.leg] or { count = 0 }
        f.legEvidence[f.leg] = evidence
        if frame.bodyDot then evidence.count = evidence.count + 1 end
        if frame.proven then evidence.proven = true end
        f.samples = (f.samples or 0) + 1
        if frame.bodyDot then f.rendered = (f.rendered or 0) + 1 end
        if frame.bodyDot and frame.bodyDot < -0.5 then
            f.backward = (f.backward or 0) + 1
            f.backwardSince = f.backwardSince or current
            f.longestBackward = math.max(f.longestBackward or 0, current - f.backwardSince)
        else f.backwardSince = nil end
        local decision = SC.Decision.peek(f.actor) or {}
        local nav = SC.Navigation.status(f.actor) or {}
        print("SC_FACING|SAMPLE|leg=" .. f.leg .. "|ms=" .. (current - f.legAt)
            .. "|point=" .. frame.x .. "," .. frame.y .. "|delta=" .. frame.dx .. "," .. frame.dy
            .. "|forward_dot=" .. tostring(frame.forwardDot) .. "|body_dot=" .. tostring(frame.bodyDot)
            .. "|angle=" .. tostring(frame.angle) .. "|body_proven=" .. tostring(frame.proven)
            .. "|aiming=" .. tostring(f.actor:isAiming()) .. "|nav=" .. tostring(nav.phase)
            .. "|intent=" .. tostring(decision.intent))
        if current >= f.pictureAt and current - f.legAt <= 14000 then
            getCore():TakeFullScreenshot(H.config.run_id .. "-facing-leg-" .. f.leg .. "-" .. math.floor((current - f.legAt) / 1000) .. ".png")
            f.pictureAt = current + 1500
        end
    else f.backwardSince = nil end
    local tx, ty = f.target:getX() + 0.5, f.target:getY() + 0.5
    if (f.actor:getX() - tx)^2 + (f.actor:getY() - ty)^2 < 1 then
        if f.leg == 1 then
            f.leg = 2
            local good, why = order(SC, H, f, current)
            if not good then finish(H, current, check, result, setPhase, false, tostring(why)) end
        else
            local first, second = f.legEvidence and f.legEvidence[1], f.legEvidence and f.legEvidence[2]
            local good = first and second and first.count >= 8 and second.count >= 8 and first.proven and second.proven
                and (f.longestBackward or 0) < 1000 and (f.backward or 0) <= math.max(3, (f.rendered or 0) * 0.1)
            finish(H, current, check, result, setPhase, good, "two public Move here legs; native rendered facing observations")
        end
    end
end
SCRealSandboxHarnessProbes.SCFacingProbe = Probe
return Probe
