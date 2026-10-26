-- SPDX-License-Identifier: MIT
-- Native-client lifecycle checks in a disposable clone. No damage is staged.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance then
    require "SCBanditsCombatAcceptance"
end
local Probe = {}
local Shared = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.shared
local function occurrences(list, actor)
    local count = 0
    for index = 0, list:size() - 1 do if list:get(index) == actor then count = count + 1 end end
    return count
end
local function finish(H, current, check, result, setPhase, okay, why)
    local f = H.banditsLifecycle
    if f then
        okay = check("lifecycle_primary_isolation", Shared.samePlayers(f.primary),
            "native main-player identity, slots and count unchanged") and okay
        okay = check("lifecycle_command_binding", sendClientCommand == f.command,
            "native command binding unchanged; no damage callback invoked") and okay
    end
    result(okay and "PASS" or "FAIL", "bandits_live_lifecycle", why)
    setPhase("finish", current)
end
function Probe.step(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.banditsLifecycle
    if not f then
        if current - H.startedAt < 10000 or not SC.State.active or SC.Registry.count() == 0 then return end
        if not check("lifecycle_adapter_active", SC.BanditsAdapter.status().active,
            SC.BanditsAdapter.status().reason) then setPhase("finish", current) return end
        local primary = Shared.playerState()
        local site = Shared.field(SC, primary.player)
        if not site then finish(H, current, check, result, setPhase, false, "no loaded native spawn site") return end
        local ticket, reason = SC.Actor.beginSpawn(site.fellow,
            { recruited = true, identity = SC.Spawn.generateIdentity() })
        if not ticket then finish(H, current, check, result, setPhase, false, tostring(reason)) return end
        H.banditsLifecycle = { primary = primary, ticket = ticket, command = sendClientCommand, started = current }
        return
    end
    local actor, reason = SC.Actor.pollSpawn(f.ticket)
    if not actor then
        if reason ~= "spawn_pending" or current - f.started > 30000 then
            finish(H, current, check, result, setPhase, false, "native actor: " .. tostring(reason))
        end
        return
    end
    local adapter = SC.BanditsAdapter
    local alias = BanditUtils.GetCharacterID(actor)
    local good = check("lifecycle_alias", alias == "lf:" .. SC.Registry.idOf(actor)
        and BanditPlayer.GetPlayerById(alias) == actor and occurrences(BanditPlayer.GetPlayers(), actor) == 1,
        "fresh living native actor resolves exactly once: " .. tostring(alias))
    local lookup, players, model = BanditPlayer.GetPlayerById, BanditPlayer.GetPlayers, PlayerDamageModel.MeleeHit
    for _ = 1, 3 do adapter.initialize() end
    good = check("lifecycle_repeated_init", BanditPlayer.GetPlayerById == lookup and BanditPlayer.GetPlayers == players
        and PlayerDamageModel.MeleeHit == model and occurrences(BanditPlayer.GetPlayers(), actor) == 1,
        "three initializations retain one wrapper and one native actor entry") and good

    local option = PZAPI.ModOptions:getOptions("SurvivorCompanion"):getOption("banditsCompatibility")
    local prior = option:getValue()
    local okay, why = pcall(function()
        option:setValue(false)
        SC.UserOptions.apply()
        good = check("lifecycle_option_off", adapter.status().state == "disabled"
            and BanditPlayer.GetPlayerById(alias) == nil and occurrences(BanditPlayer.GetPlayers(), actor) == 0,
            "real Mods option removes LF targeting while retaining alias safety") and good
        option:setValue(true)
        SC.UserOptions.apply()
        good = check("lifecycle_option_on", adapter.status().active and BanditPlayer.GetPlayerById(alias) == actor,
            "real Mods option restores the existing native actor") and good
    end)
    option:setValue(prior)
    SC.UserOptions.apply()
    if not okay then finish(H, current, check, result, setPhase, false, "option check: " .. tostring(why)) return end

    local originalDamage = BanditServer.Commands.PlayerDamage
    okay, why = pcall(function()
        BanditServer.Commands.PlayerDamage = nil
        adapter.initialize()
        good = check("lifecycle_unsupported", adapter.status().state == "unsupported"
            and type(adapter.status().reason) == "string" and BanditPlayer.GetPlayerById(alias) == nil,
            "missing required native interface disables integration with readable diagnostic: " .. tostring(adapter.status().reason)) and good
    end)
    BanditServer.Commands.PlayerDamage = originalDamage
    adapter.initialize()
    if not okay then finish(H, current, check, result, setPhase, false, "interface check: " .. tostring(why)) return end
    good = check("lifecycle_interface_restored", adapter.status().active and BanditPlayer.GetPlayerById(alias) == actor,
        "restored native interface reactivates without replacing the actor") and good

    local retainedLookup = BanditPlayer.GetPlayerById
    adapter.reset()
    good = check("lifecycle_retired_alias", retainedLookup(alias) == nil,
        "retained retired alias lookup never falls through to single-player ID 1") and good
    adapter.initialize()
    good = check("lifecycle_reset_reinit", adapter.status().active and BanditPlayer.GetPlayerById(alias) == actor
        and retainedLookup(alias) == nil and BanditUtils.GetCharacterID(f.primary.player) == 1,
        "fresh wrappers resolve LF; retired wrappers stay inert; main identity remains 1") and good

    actor:removeFromWorld()
    actor:removeFromSquare()
    adapter.invalidate()
    local worldGone, resolved, listed = actor:isExistInTheWorld() == false,
        BanditPlayer.GetPlayerById(alias), occurrences(BanditPlayer.GetPlayers(), actor)
    good = check("lifecycle_native_despawn", worldGone and resolved == nil and listed == 0,
        "native world/square removal before registry cleanup: gone=" .. tostring(worldGone)
            .. "; resolved=" .. tostring(resolved) .. "; listed=" .. listed) and good
    local removed = SC.Actor.remove(actor)
    good = check("lifecycle_registry_cleanup", removed == true and BanditPlayer.GetPlayerById(alias) == nil
        and retainedLookup(alias) == nil, "removed alias cannot resolve to the main player") and good
    finish(H, current, check, result, setPhase, good, "native-client identity, options, missing interface, reset and despawn checks")
end
SCRealSandboxHarnessProbes.SCBanditsLifecycleAcceptance = Probe
return Probe
