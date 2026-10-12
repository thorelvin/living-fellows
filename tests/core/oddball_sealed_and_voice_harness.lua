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
local seeded, seedReason = Survivalist.onSpawn(F.caleb, F.records.caleb.actor)
check(seeded == true and F.door.locked and F.door.lockedByKey,
    "room door is truly locked before horde seeding: " .. tostring(seedReason))
check(#F.zombies == 20 and F.caleb.oddball.hordeCount == 20,
    "twenty real tagged zombies appear in the sealed room")
for _, zombie in ipairs(F.zombies) do
    check(zombie.data.lfSealedHordeGroupId == F.caleb.id,
        "horde member keeps scene identity")
end
Survivalist.onSpawn(F.caleb, F.records.caleb.actor)
check(#F.zombies == 20, "reload does not duplicate the horde")
F.doorLoaded = false
Survivalist.pulse(F.caleb, F.player, F.now)
check(F.caleb.oddball.sealBroken ~= true and F.released == 0,
    "an unresolved sealed door does not release Caleb or the horde")
F.doorLoaded = true
Survivalist.pulse(F.caleb, F.player, F.now)
check(#F.lines >= 1 and string.find(F.lines[1].line, "twenty", 1, true),
    "Caleb warns the player")
check(#F.clicks == 1, "door click hook is registered once")
F.clicks[1](F.door)
check(F.caleb.oddball.stage == "fleeing" and F.released == 0,
    "touching the exact door makes him flee without unlocking it")
F.door.locked = false
local resumed, resumedReason = Survivalist.onSpawn(F.caleb,
    F.records.caleb.actor)
check(resumed == true and resumedReason == "sealed_room_already_resolved"
    and F.door.locked == false and #F.zombies == 20,
    "reload after Caleb flees preserves the player's unlocked door")
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
F.door.locked = false
Survivalist.onSpawn(F.caleb, F.records.caleb.actor)
check(F.door.locked == false and #F.zombies == 20,
    "reload after a breach never re-locks the horde room")
Survivalist.remove()
check(#F.clicks == 0, "door click hook can be removed")

F.player.x, F.player.y = 21, 20
VoiceActor.pulse(F.vera, F.player, F.now)
check(F.vera.oddball.bedroomOpen ~= true and F.released == 1,
    "unresolved bedroom door does not release Vera's protection")
F.voiceDoorLoaded = true
VoiceActor.pulse(F.vera, F.player, F.now)
check(F.vera.oddball.bedroomOpen ~= true and F.released == 1,
    "a verified closed bedroom door remains protected")
F.voiceDoor.open = true
VoiceActor.pulse(F.vera, F.player, F.now)
check(F.vera.oddball.bedroomOpen == true and F.released == 2,
    "opening the actual bedroom door releases protection once")
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

F.door.open = false
F.door.locked = false
F.zombieSpawnFailures = 1
local partial = { id = "partially-seeded-group",
    members = F.caleb.members, oddball = {
        id = "survivalist_locked_horde", site = F.caleb.oddball.site,
    } }
local beforePartial = #F.zombies
Survivalist.onSpawn(partial, F.records.caleb.actor)
check(partial.oddball.hordeCount == 19
    and #F.zombies == beforePartial + 19,
    "a transient native spawn failure records the nineteen actual zombies")
Survivalist.onSpawn(partial, F.records.caleb.actor)
check(partial.oddball.hordeCount == 20
    and #F.zombies == beforePartial + 20,
    "a later intact-seal spawn fills only the missing zombie")
Survivalist.onSpawn(partial, F.records.caleb.actor)
check(#F.zombies == beforePartial + 20,
    "a completed horde never duplicates on another load")
F.legacyRoomLoaded = true
F.door.open, F.door.locked = false, false
local legacy = { id = "legacy-sealed-group", members = F.caleb.members,
    oddball = { id = "survivalist_locked_horde", site = {
        roomDoor = F.caleb.oddball.site.roomDoor,
        sealedRoom = { x = 10, y = 9, z = 0 },
    } } }
local beforeLegacy = #F.zombies
check(Survivalist.onSpawn(legacy, F.records.caleb.actor) == true
    and #legacy.oddball.site.hordeSpawns == 4
    and #F.zombies == beforeLegacy + 20,
    "a loaded legacy sealed room rebuilds missing posts and seeds the horde")
print("PASS: " .. checks .. " sealed-room and voice-actor checks")
