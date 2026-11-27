-- SPDX-License-Identifier: MIT
-- Loaded in a disposable world to verify the official optimizer or Workshop preloader.
local SC = LivingFellows
local state = { phase = "menu", zombies = {}, priorHits = {}, priorAttacks = {},
    targetTicks = 0, starts = 0, hits = 0, fallbackWounds = 0 }
local SAVE = "OptimizerCombatFixture"

local function write(name, content)
    local file = assert(getFileWriter(name, true, false))
    file:write(content .. "\n")
    file:close()
end

local function phase(name)
    state.phase, state.since = name, getTimestampMs()
    write("optimizer-progress.txt", name)
    print("SC_OPT_ACCEPTANCE " .. name)
end

local function finish(result, reason)
    state.done = true
    local elapsed = state.started and (getTimestampMs() - state.started) or 0
    local report = table.concat({ "result=" .. result, "mode=" .. tostring(state.mode),
        "phase=" .. state.phase, "reason=" .. tostring(reason),
        "adapter=" .. tostring(state.adapter), "adapter_reason=" .. tostring(state.adapterReason),
        "natural_target_ticks=" .. state.targetTicks, "attack_starts=" .. state.starts,
        "native_impact_events=" .. state.hits, "fallback_wounds=" .. state.fallbackWounds,
        "body_wound_parts=" .. tostring(state.wounds), "health_loss=" .. tostring(state.healthLoss),
        "inline_calls=" .. tostring(state.inline), "elapsed_ms=" .. elapsed,
    }, "\n")
    write("optimizer-result.txt", report)
    print("SC_OPT_ACCEPTANCE " .. report:gsub("\n", " "))
end

local function wounds(actor)
    local body = actor:getBodyDamage()
    return body:getNumPartsBitten() + body:getNumPartsScratched() + body:getNumPartsBleeding()
end

local function arena(player)
    local U = SC.GameplayUtil
    local cx, cy = math.floor(player:getX()), math.floor(player:getY())
    for radius = 8, 34, 2 do
        for step = 0, 15 do
            local angle = step * math.pi / 8
            local x = cx + math.floor(math.cos(angle) * radius + 0.5)
            local y = cy + math.floor(math.sin(angle) * radius + 0.5)
            local clear = true
            for dx = -4, 4 do
                for dy = -4, 4 do
                    local square = U.gridSquare(x + dx, y + dy, 0)
                    if not square or not square:isOutside() or not U.isSquareFree(square)
                        or SC.Topology.squareIsWater(square) then clear = false; break end
                end
                if not clear then break end
            end
            if clear then return U.gridSquare(x, y, 0) end
        end
    end
end

local function spawnZombies(square)
    local x, y = square:getX(), square:getY()
    for _, offset in ipairs({ { 4, 0 }, { 0, -4 }, { -4, 0 } }) do
        local list = assert(addZombiesInOutfit(x + offset[1], y + offset[2], 0, 1, nil, 0))
        state.zombies[#state.zombies + 1] = assert(list:get(0), "could not spawn a stock zombie")
    end
end

local function step()
    local now = getTimestampMs()
    local U = SC.GameplayUtil
    if state.phase == "load" then
        if now - state.since < 6500 then return end
        assert(SCBridge and ZombieBuddy, "game did not load LF through ZombieBuddy")
        assert(not SCBridge.isCompanion(state.player) and state.player:getPlayerNum() == 0,
            "primary player identity changed before the trial")
        SCBridge.configurePZOptimizerAdapter(state.mode == "enabled" or state.mode == "inactive" or state.mode == "coexist")
        state.adapter = SCBridge.getPZOptimizerAdapterState()
        state.adapterReason = SCBridge.getPZOptimizerAdapterReason()
        if state.mode == "inactive" then
            assert(state.adapter ~= "active", "inactive optimizer was accepted")
            finish("PASS", "inactive_optimizer_rejected")
            return
        end
        local expected = state.mode == "enabled" and "active" or "disabled"
        if state.mode == "coexist" then
            assert(state.adapter ~= "active", "official agent adapter unexpectedly claimed the preloader")
        else
            assert(state.adapter == expected, state.adapterReason)
        end
        state.inlineBefore = SCBridge.getPZOptimizerInlineCalls()
        state.square = assert(arena(state.player), "no clear loaded combat arena")
        for _, actor in ipairs(SC.Registry.living()) do SC.Actor.remove(actor) end
        local ticket, reason = SC.Actor.beginSpawn(state.square, { recruited = true,
            identity = { forename = "Evan", surname = "Trial", gender = "male", outfit = "Generic01" } })
        assert(ticket, reason)
        state.ticket = ticket
        phase("spawn")
    elseif state.phase == "spawn" then
        local actor, reason = SC.Actor.pollSpawn(state.ticket)
        if not actor then
            assert(reason == "spawn_pending" and now - state.since < 15000, reason)
            return
        end
        state.actor = actor
        assert(SCBridge.isCompanion(actor), "trial body has no native LF ownership")
        assert(SC.Commands.issue(SC.Registry.idOf(actor), "stay", nil, state.player))
        local supervisor = SC.ActionSupervisor
        supervisor.cancel(actor, "optimizer_incoming_attack_control", nil, true)
        assert(supervisor.begin(actor, { owner = "live_harness", action = "optimizer_incoming_attack_control",
            priority = supervisor.Priority.EXTERNAL, phase = "approaching", interruptible = false,
            ignoreRetry = true, deadlines = { approaching = 65000 },
            allowedMovementPhases = { approaching = true } }))
        SC.Actor.stop(actor)
        state.initialHealth, state.initialWounds = U.nativeHealth(actor), wounds(actor)
        spawnZombies(state.square)
        state.started = now
        phase("observe")
    elseif state.phase == "observe" then
        local actor = state.actor
        for _, zombie in ipairs(state.zombies) do
            if zombie:getTarget() == actor then
                state.targetTicks = state.targetTicks + 1
                local attacking = zombie:getVariableBoolean("bAttack")
                    or tostring(zombie:getCurrentStateName()):lower():find("attack", 1, true) ~= nil
                local hit = zombie:getVariableBoolean("AttackDidDamage")
                if attacking and not state.priorAttacks[zombie] then state.starts = state.starts + 1 end
                if hit and not state.priorHits[zombie] then state.hits = state.hits + 1 end
                state.priorAttacks[zombie], state.priorHits[zombie] = attacking, hit
            else
                state.priorAttacks[zombie], state.priorHits[zombie] = nil, nil
            end
        end
        state.wounds = wounds(actor) - state.initialWounds
        state.healthLoss = state.initialHealth - U.nativeHealth(actor)
        state.inline = SCBridge.getPZOptimizerInlineCalls() - state.inlineBefore
        if (state.mode == "enabled" or state.mode == "coexist")
            and state.hits > 0 and state.wounds > 0 and state.healthLoss > 0 then
            assert(state.fallbackWounds == 0, "expected native damage without synthetic fallback")
            if state.mode == "coexist" then
                assert(state.inline == 0, "preloader coexistence used the LF inline path")
            else
                assert(state.inline > 0, "native result did not isolate the patched path")
            end
            assert(not SCBridge.isCompanion(state.player) and state.player:getPlayerNum() == 0,
                "primary player identity changed during combat")
            finish("PASS", "native_impact_and_wound")
        elseif now - state.started >= 45000 or actor:isDead() then
            assert(state.targetTicks > 0 and state.starts > 0, "zombies never acquired and attacked the companion")
            if state.mode == "disabled" then
                assert(state.inline == 0, "disabled adapter intercepted a submission")
                finish("PASS", "disabled_control_observed")
            else
                finish("FAIL", "native impact and wound were not observed")
            end
        end
    end
end

Events.OnMainMenuEnter.Add(function() MainScreen.continueLatestSave("Sandbox", SAVE) end)
local shown = {}
Events.OnRenderTick.Add(function()
    local modal = MainScreen and MainScreen.instance and MainScreen.instance.checkSavefileModal
    if modal and modal.yes and not shown[modal] then shown[modal] = true; modal:onClick(modal.yes) end
end)
Events.OnGameStart.Add(function()
    local file = assert(getFileReader("optimizer-mode.txt", false))
    state.mode = file:readLine()
    file:close()
    state.player = assert(getSpecificPlayer(0))
    state.player:setGhostMode(true)
    state.player:setInvisible(true)
    local resolve = SC.ZombieAttack.resolve
    SC.ZombieAttack.resolve = function(actor, ...)
        local okay, reason, receipt = resolve(actor, ...)
        if actor == state.actor and receipt then
            state.fallbackWounds = state.fallbackWounds + (receipt.applied or 0)
        end
        return okay, reason, receipt
    end
    phase("load")
end)
Events.OnTick.Add(function()
    if state.done or state.phase == "menu" then return end
    local okay, reason = pcall(step)
    if not okay then finish("FAIL", reason) end
end)
