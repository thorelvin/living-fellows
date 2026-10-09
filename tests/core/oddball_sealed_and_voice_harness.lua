-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local F = SealedVoiceFixture
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "sealed/voice check " .. checks .. ": " .. message)
end
local Survivalist = SC.OddballSurvivalist
local VoiceActor = SC.OddballVoiceActor
local seeded = Survivalist.onSpawn(F.caleb, F.records.caleb.actor)
check(seeded == true and F.door.locked and F.door.lockedByKey,
    "room door is truly locked before horde seeding")
check(#F.zombies == 20 and F.caleb.oddball.hordeCount == 20,
    "twenty real tagged zombies appear in the sealed room")
for _, zombie in ipairs(F.zombies) do
    check(zombie.data.lfSealedHordeGroupId == F.caleb.id,
        "horde member keeps scene identity")
end
Survivalist.onSpawn(F.caleb, F.records.caleb.actor)
check(#F.zombies == 20, "reload does not duplicate the horde")
Survivalist.pulse(F.caleb, F.player, F.now)
check(#F.lines >= 1 and string.find(F.lines[1].line, "twenty", 1, true),
    "Caleb warns the player")
check(#F.clicks == 1, "door click hook is registered once")
F.clicks[1](F.door)
check(F.caleb.oddball.stage == "fleeing" and F.released == 0,
    "touching the exact door makes him flee without unlocking it")
local intent = Survivalist.intentFor(F.records.caleb.actor, F.player,
    nil, F.caleb)
check(intent.mode == "survivalist_flee", "escape receives movement intent")
Survivalist.update(F.records.caleb.actor, F.player, nil, intent, F.caleb)
check(#F.routes == 1 and F.routes[1].pace == "run",
    "escape runs through shared navigation")
F.door.open = true
Survivalist.pulse(F.caleb, F.player, F.now + 1000)
check(F.caleb.oddball.sealBroken and F.released == 1,
    "opening the room releases the horde protection")
Survivalist.remove()
check(#F.clicks == 0, "door click hook can be removed")

F.player.x, F.player.y = 21, 20
VoiceActor.pulse(F.vera, F.player, F.now)
check(F.sounds[1] == "FemaleZombieVoiceA",
    "Vera emits a real zombie voice event from her actor")
check(VoiceActor.menuOptions(F.vera, F.player)[1].id == "confront",
    "player can confront her")
local accepted = VoiceActor.action(F.vera, "confront", F.player)
check(accepted and F.vera.oddball.confronted and
    F.vera.oddball.lineIndex == 2, "confrontation starts persistent story")
F.now = F.now + 10000
VoiceActor.pulse(F.vera, F.player, F.now)
check(F.vera.oddball.lineIndex == 3,
    "story continues on later pulses without repeating first line")
check(VoiceActor.canRecruit(F.vera) == false,
    "Vera remains a neutral resident")
print("PASS: " .. checks .. " sealed-room and voice-actor checks")
