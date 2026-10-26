-- SPDX-License-Identifier: MIT
local SC, checks = SurvivorCompanion, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "Installed Bandits source check " .. checks .. ": " .. message)
end
local control = BANDITS_TEST_ACTOR()
local victim = BANDITS_TEST_ACTOR("sc-installed-bandits-victim")
local sourcePlayerID = BanditUtils.GetCharacterID
check(sourcePlayerID(control) == 1 and sourcePlayerID(victim) == 1,
    "installed Bandits reproduces the real SP identity collision")
local handler = BanditServer.Commands.PlayerDamage
local sent, routed = 0, 0
sendClientCommand = function(player, module, command, args)
    assert(module == "Commands" and command == "PlayerDamage")
    sent = sent + 1
    handler(player, args)
end
BanditServer.Commands.PlayerDamage = function(player, args)
    routed = routed + 1
    assert(player == victim, "NPC command cannot select the main player")
    return handler(player, args)
end
local originalCommand = sendClientCommand
check(SC.BanditsAdapter.initialize(), "current source profile activates")
check(BanditUtils.GetCharacterID(victim) == "lf:sc-installed-bandits-victim",
    "installed character lookup receives a distinct LF identity")
check(BanditPlayer.GetPlayerById("lf:sc-installed-bandits-victim") == victim,
    "installed attack target lookup resolves the exact actor")
check(BanditPlayer.GetPlayerById(1) == BANDITS_TEST_PLAYER and BANDITS_TEST_REAL_LIST:size() == 1,
    "installed player lookup and native list remain unchanged")
local weapon = { getMinDamage = function() return 1 end, getMaxDamage = function() return 1 end,
    isDamageMakeHole = function() return true end }
for _, armoured in ipairs({ false, true }) do
    for _, name in ipairs({ "BulletHit", "BareHandHit", "MeleeHit" }) do
        local actual, expected = BANDITS_SOURCE_BODY(victim), BANDITS_SOURCE_BODY(control)
        victim.armour, control.armour = armoured and 100 or 0, armoured and 100 or 0
        victim.holes, control.holes, victim.blood, control.blood = 0, 0, false, false
        local priorRouted, priorSent = routed, sent
        if name == "BulletHit" then
            PlayerDamageModel[name]({}, weapon, control)
            PlayerDamageModel[name]({}, weapon, victim)
        elseif name == "BareHandHit" then
            PlayerDamageModel[name]({}, control)
            PlayerDamageModel[name]({}, victim)
        else
            PlayerDamageModel[name]({}, control, weapon)
            PlayerDamageModel[name]({}, victim, weapon)
        end
        check(actual.health == expected.health, name .. " uses the original wound/armour calculation")
        check(routed == priorRouted + 1 and sent == priorSent + 1,
            name .. " delivers NPC damage once without a player command")
        check(victim.holes == control.holes and victim.blood == control.blood,
            name .. " preserves clothing and blood effects")
        for index = 0, actual.parts:size() - 1 do
            local a, e = actual.parts:get(index), expected.parts:get(index)
            check(a.cut == e.cut and a.scratched == e.scratched and a.deepWound == e.deepWound
                and a.bullet == e.bullet, name .. " preserves exact body-part wound state")
        end
        check(sendClientCommand == originalCommand, "original command binding restored")
    end
end
SC_TEST_REPORT = "BANDITS_INSTALLED_SOURCE_PASS checks=" .. checks
