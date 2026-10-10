-- SPDX-License-Identifier: MIT
-- Run in a disposable save: exercise vanilla Mod Options Apply against a real
-- native companion, including the player-hit veto and ordinary-cold clearing.
local Probe = {}

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function spawnSquare(player)
    local utility = SurvivorCompanion.GameplayUtil
    local x, y, z = math.floor(player:getX()), math.floor(player:getY()),
        math.floor(player:getZ())
    for radius = 1, 6 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    if square and utility.isSquareFree(square)
                        and call(square, "isFree", true) ~= false
                        and call(square, "isSafeToSpawn") ~= false then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

local function restore(H)
    if not H.userOptionsSaved then return end
    local saved, options = H.userOptionsSaved, H.userOptionsGroup
    options:getOption("chatter"):setValue(saved.chatter)
    options:getOption("coughSneezes"):setValue(saved.coughSneezes)
    options:getOption("ordinaryColds"):setValue(saved.ordinaryColds)
    options:getOption("protectRecruitedCompanions"):setValue(saved.protect)
    options:apply()
    H.userOptionsSaved = nil
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "user_options_setup" then
        if current - H.phaseStartedAt < 3000 then return end
        local options = PZAPI and PZAPI.ModOptions
            and PZAPI.ModOptions:getOptions("SurvivorCompanion")
        if not check("mod_options_registered", options ~= nil,
            "Options > Mods contains Living Fellows") then
            setPhase("finish", current) return
        end
        H.userOptionsGroup = options
        H.userOptionsSaved = {
            chatter = options:getOption("chatter"):getValue(),
            coughSneezes = options:getOption("coughSneezes"):getValue(),
            ordinaryColds = options:getOption("ordinaryColds"):getValue(),
            protect = options:getOption("protectRecruitedCompanions"):getValue(),
        }
        local square = spawnSquare(H.player)
        if not check("mod_options_spawn_square", square ~= nil,
            "nearby safe square") then
            restore(H) setPhase("finish", current) return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "Options", surname = "Tester",
                gender = "woman", outfit = "Generic01" },
        })
        if not check("mod_options_spawn_requested", ticket ~= nil,
            tostring(reason)) then
            restore(H) setPhase("finish", current) return
        end
        H.userOptionsTicket = ticket
        setPhase("user_options_spawn", current)
        return
    end

    if H.phase == "user_options_spawn" then
        local actor, reason = SC.Actor.pollSpawn(H.userOptionsTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                result("FAIL", "mod_options_spawn", tostring(reason))
                restore(H) setPhase("finish", current)
            end
            return
        end
        H.userOptionsActor = actor
        setPhase("user_options_check", current)
        return
    end

    if H.phase == "user_options_check" then
        local actor, options = H.userOptionsActor, H.userOptionsGroup
        local state = SC.Commands.peek(actor)
        local body = actor:getBodyDamage()
        check("mod_options_recruited_actor", state and state.recruited == true,
            "native companion recruited")
        -- Existing actors must react to Apply in the same frame. Seed only a
        -- disposable ordinary cold and symptom, never Knox or wound infection.
        body:setCatchACold(25.0)
        body:setHasACold(true)
        body:setColdStrength(20.0)
        body:setSneezeCoughActive(1)
        options:getOption("chatter"):setValue(2)
        options:getOption("coughSneezes"):setValue(3)
        options:getOption("ordinaryColds"):setValue(false)
        options:getOption("protectRecruitedCompanions"):setValue(true)
        options:apply()
        check("mod_options_apply_live_values",
            SC.UserOptions.get("chatter") == "less"
                and SC.UserOptions.get("coughSneezes") == "off"
                and SC.UserOptions.get("ordinaryColds") == false
                and SC.UserOptions.get("protectRecruitedCompanions") == true,
            "four current values updated")
        check("mod_options_cold_cleared",
            body:isHasACold() == false and body:getCatchACold() == 0,
            "ordinary cold cleared on Apply")
        check("mod_options_symptom_cleared",
            body:getSneezeCoughActive() == 0,
            "native symptom cleared on Apply")
        check("mod_options_native_attack_enabled",
            SCBridge.isProtectRecruitedCompanions() == true,
            "native hit gate follows Apply")
        check("mod_options_actor_marked_ally",
            actor:getModData().SC_PlayerAttackProtected == true,
            "recruited native target marked")
        local weapon = call(H.player:getInventory(), "AddItem", "Base.Crowbar")
        local healthBefore = call(body, "getOverallBodyHealth")
        local hitOk, hitResult = pcall(function()
            return actor:Hit(weapon, H.player, 0.2, false, 1.0, false)
        end)
        local healthAfter = call(body, "getOverallBodyHealth")
        check("mod_options_native_player_hit_veto",
            weapon ~= nil and hitOk and hitResult == 0.0
                and healthBefore ~= nil and healthBefore == healthAfter,
            "Hit result=" .. tostring(hitResult) .. " health="
                .. tostring(healthBefore) .. "->" .. tostring(healthAfter))
        options:getOption("protectRecruitedCompanions"):setValue(false)
        options:apply()
        local controlOk, controlResult = pcall(function()
            return actor:Hit(weapon, H.player, 0.2, false, 1.0, false)
        end)
        check("mod_options_unprotected_hit_reaches_vanilla",
            controlOk and type(controlResult) == "number" and controlResult > 0,
            "native Hit result=" .. tostring(controlResult))
        local originalProtect = H.userOptionsSaved.protect
        restore(H)
        check("mod_options_original_values_restored",
            SC.UserOptions.get("protectRecruitedCompanions")
                == originalProtect,
            "reapplied original profile values")
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCUserOptionsLiveProbe = Probe
return Probe
