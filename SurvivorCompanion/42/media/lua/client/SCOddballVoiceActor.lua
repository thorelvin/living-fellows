-- SPDX-License-Identifier: MIT
-- The sound is emitted by Vera's real actor, from her protected bedroom.
local SC = SurvivorCompanion
SC.OddballVoiceActor = SC.OddballVoiceActor or {}
local VoiceActor = SC.OddballVoiceActor
local ID = "voice_actor_vera_quill"
local VOICES = { "FemaleZombieVoiceA", "FemaleZombieVoiceB",
    "FemaleZombieVoiceC" }
local STORY = {
    "Don't shoot. That was me. I did creature voices before the world ended.",
    "Radio plays, cheap horror pictures, a few adverts nobody remembers.",
    "When the dead came, I knew the sound before I saw the first one.",
    "They came past this house. I copied them through the door. They kept walking.",
    "Sometimes I practice to remind myself my own throat still belongs to me.",
    "The hard part isn't sounding dead. It's stopping when I hear one answer.",
}
local AFTER = {
    "That one was a rehearsal. The real thing never needs one.",
    "I used to get paid for a good scream. Now I save it.",
    "Keep your voice down. Sound travels farther than kindness.",
}

local function U() return SC.GameplayUtil end
local function story(group)
    local value = group and group.oddball
    return type(value) == "table" and value.id == ID and value or nil
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function bedroomDoor(value)
    local post = value and value.site and value.site.bedroomDoor
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local door = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex)
    return door and U().instanceOf(door, "IsoDoor") and door or nil
end

function VoiceActor.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor or not player then return false, "voice_actor_unloaded" end
    if not value.bedroomOpen then
        local door = bedroomDoor(value)
        if door == nil or select(1, U().call(door, "IsOpen")) == true then
            value.bedroomOpen = true
            if SC.OddballRoomGuard then
                SC.OddballRoomGuard.release(group.id)
            end
        end
    end
    local distance = U().distance(actor, player)
    if distance <= 13 and current >= (tonumber(value.nextVoiceAt) or 0) then
        group.discovered = true
        local index = ((tonumber(value.voiceIndex) or 0) % #VOICES) + 1
        value.voiceIndex = index
        local _, played = U().call(actor, "playSound", VOICES[index])
        if not played and SC.Diagnostics
            and type(SC.Diagnostics.report) == "function"
            and not value.soundFailureReported then
            value.soundFailureReported = true
            SC.Diagnostics.report("oddballs", group.id,
                "Vera's zombie voice sound was unavailable", VOICES[index])
        end
        value.nextVoiceAt = current + (value.confronted and 65000 or 22000)
    end
    if value.confronted and value.lineIndex
        and value.lineIndex <= #STORY and near(group, player, 8)
        and current >= (tonumber(value.nextLineAt) or 0) then
        U().say(actor, STORY[value.lineIndex])
        value.lineIndex = value.lineIndex + 1
        value.nextLineAt = current + 9500
    elseif value.confronted and value.lineIndex
        and value.lineIndex > #STORY and near(group, player, 8)
        and current >= (tonumber(value.nextAsideAt) or 0) then
        local index = ((tonumber(value.asideIndex) or 0) % #AFTER) + 1
        value.asideIndex = index
        U().say(actor, AFTER[index])
        value.nextAsideAt = current + 90000
    end
    return true, value.confronted and "voice_actor_known" or "zombie_imitation"
end

function VoiceActor.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    local threats = snapshot and (tonumber(snapshot.threatCount)
        or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "oddball_idle", priority = 28 }
end

function VoiceActor.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7) then return {} end
    return { { id = value.confronted and "ask_voice" or "confront",
        label = value.confronted and "Ask Vera to do the voice again"
            or "Confront the woman making zombie sounds",
        enabled = true } }
end

function VoiceActor.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if actor then U().say(actor, "I'm alive! That's my voice, not a bite!") end
        return true, "voice_actor_not_hostile"
    end
    if not actor or not near(group, player, 7) then
        return false, "voice_actor_too_far" end
    if action == "confront" then
        value.confronted = true
        value.lineIndex = 1
        value.nextLineAt = U().nowMs()
        value.nextVoiceAt = U().nowMs() + 65000
        group.discovered = true
        U().say(actor, STORY[1])
        value.lineIndex = 2
        value.nextLineAt = U().nowMs() + 9500
        return true, "voice_actor_revealed"
    elseif action == "ask_voice" then
        local index = ((tonumber(value.voiceIndex) or 0) % #VOICES) + 1
        value.voiceIndex = index
        U().call(actor, "playSound", VOICES[index])
        value.nextVoiceAt = U().nowMs() + 65000
        return true, "voice_actor_demonstrated"
    end
    return false, "unknown_voice_actor_action"
end

function VoiceActor.canRecruit()
    return false, "voice_actor_will_stay_in_her_room"
end

return VoiceActor
