-- SPDX-License-Identifier: MIT
-- Hershel Combs sits on a bathroom floor with a real zombie bite on his left
-- forearm. The bite is vanilla BodyPart.SetBitten, so BodyDamage.Update runs
-- the infection on the sandbox's own clock and the sandbox decides whether
-- his body gets back up. He asks for a mercy kill; the player can give it,
-- refuse it, or leave him to the infection.

local SC = SurvivorCompanion
SC.OddballBitten = SC.OddballBitten or {}
local Bitten = SC.OddballBitten

local ID = "bitten_hershel_combs"
local NEAR_DISTANCE = 6
local MENU_DISTANCE = 4
local LEFT_DISTANCE = 12
local RETURN_GRACE_MS = 30000
local TALK_MS = 38000
local TALK_SPREAD_MS = 9000
local INTRO_GAP_MS = 5500
local SIT_RETRY_MS = 12000
local SIT_ATTEMPTS = 4
local LATE_INFECTION = 85
local BANDAGE_LIFE = 2

local LINES = {
    greet = {
        "Don't run. I'm not getting up. Can't, mostly.",
    },
    intro = {
        "Name's Hershel. Got bit nine days ago. I've been counting.",
        "I need a favor. The kind you don't ask twice.",
    },
    plea = {
        "Nine days. Way I heard it, folks don't last three. I'm slow at this too.",
        "I tried doing it myself. Twice. My hands got opinions.",
        "I keep waiting to get hungry for the wrong thing.",
        "Whatever you're carrying will do. I won't hold it against you.",
        "Don't make a speech. I've talked to this wall nine days. It's heard enough.",
        "Every time I nod off, I wake up checking if I'm still me.",
        "Fixed televisions thirty years. Never fixed one by hitting it. Try anyway.",
        "Ain't asking you to like it. Asking you to do it.",
        "You leave, I finish this alone on a bathroom floor. That's a schedule.",
        "Folks used to do each other favors. Help move a couch. This is the couch.",
        "Close your eyes if you want. I'll keep mine open.",
        { "Hurts like hell. Not the arm. The waiting.",
            clean = "Hurts like heck. Not the arm. The waiting." },
        "Lois always said I'd be late to my own funeral. Help me be on time.",
        { "Nine goddamn days on a bathroom floor. Don't let it be ten.",
            clean = "Nine darn days on a bathroom floor. Don't let it be ten." },
    },
    fever = {
        "Is it hot in here, or is that just me dying?",
        "Don't mind the shakes. They come and go. Mostly come.",
        "I can hear my heart in my teeth.",
        "Everything's too bright. Even the dark's too bright.",
        "Mouth tastes like pennies. Been tasting pennies since day four.",
    },
    late = {
        "Getting cold. Room's getting far away. Now would be good.",
        "Can't feel my hands. That's new. Ain't good new.",
        "Whatever you're gonna do, do it before I stop asking.",
    },
    bite = {
        "Grocery lot. Mrs. Dabney from church. Dead a day and still holding her purse.",
        "She took a piece of my arm and kept hold of her purse. Priorities.",
    },
    count = {
        "I count every time I wake up. Could be I wake up a lot.",
        "Wrote it all down. Notebook's in my pocket. Read it after.",
    },
    sit = {
        "Then sit. Tell me something that ain't about this.",
    },
    sitAfter = {
        "That's nice. Didn't hear a word. Was nice anyway.",
    },
    refuse = {
        "Then go. Shut the door behind you. I'll keep.",
        "Still no? Then quit standing in my light.",
    },
    mercy = {
        "Thank you. Do it right, so I stay down.",
    },
    hurt = {
        "There it is. Don't stop halfway, that's worse.",
        "Again. You're doing fine.",
        "Harder. I won't tell anybody.",
    },
    back = {
        "You came back. Change your mind, or forget something?",
        "Door was open. Figured it was you or the other thing.",
    },
    fellowMeet = {
        "Bites don't take nine days. He's counting wrong, or lying.",
        "Don't look at me. I'm not saying no, either.",
    },
    fellowMercy = {
        "That was the decent thing. He's staying down. Nine days was enough.",
    },
}
Bitten.LINES = LINES

-- His notebook is real, readable paper. Nine pages, one per day he counted.
local PAGES = {
    "Day 1. Mrs. Dabney from church bit me in the grocery lot. Dead a day. Still had her purse.",
    "Day 2. Fever. Wrapped it. Told myself it was a dog.",
    "Day 3. It was not a dog.",
    "Day 4. Can't keep water down. Wrote Lois a letter. No stamps. No Lois.",
    "Day 5. Tried to do it myself. Couldn't.",
    "Day 6. Heard them at the door all night. They don't knock right.",
    "Day 7. Or day 6 again. Hard to say. Counting twice to be sure.",
    "Day 8. Still me. I think. Somebody come.",
    "Day 9. If you're reading this and I'm on the floor, I'm sorry about the floor.",
}
Bitten.PAGES = PAGES

local sitByActor = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "waiting" end
    value.lines = type(value.lines) == "table" and value.lines or {}
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function lineText(entry)
    if type(entry) == "table" then
        return U().config("profanityEnabled") == false and entry.clean or entry[1]
    end
    return entry
end

local function nextLine(value, pool)
    local list = LINES[pool]
    local index = tonumber(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return lineText(list[index])
end

local function speak(actor, value, pool)
    if not actor then return false end
    return U().say(actor, nextLine(value, pool)) == true
end

local function fellowLine(group, player, pool, flag)
    local value = story(group)
    if not value or value[flag] == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local hershel = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= hershel and U().distance(fellow, player) <= 8 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, nextLine(value, pool))
                value[flag] = true
                return true
            end
        end
    end
    return false
end

-- Only seed him where a bite is fatal: transmission by blood and saliva or
-- saliva only, and a mortality that is neither instant nor never.
function Bitten.bitesInfect()
    local lore = type(SandboxVars) == "table" and SandboxVars.ZombieLore or nil
    local transmission = tonumber(type(lore) == "table" and lore.Transmission or nil)
    local mortality = tonumber(type(lore) == "table" and lore.Mortality or nil)
    return (transmission == 1 or transmission == 2)
        and mortality ~= nil and mortality ~= 1 and mortality ~= 7
end

local function syncShelter(actor, wanted)
    if not actor or not SC.Oddballs
        or type(SC.Oddballs.setZombieShelter) ~= "function" then
        return false
    end
    local actual, readable = U().call(actor, "isZombiesDontAttack")
    if readable and actual == wanted then return true end
    return SC.Oddballs.setZombieShelter(actor, wanted) == true
end

local function forearm(actor)
    local body = select(1, U().call(actor, "getBodyDamage"))
    local kind = BodyPartType and BodyPartType.ForeArm_L or nil
    if not body or kind == nil then return nil end
    return select(1, U().call(body, "getBodyPart", kind))
end

local function applyBite(actor, value)
    if value.biteApplied == true then return true end
    local part = forearm(actor)
    if not part then return false end
    -- The same call a zombie's bite makes. BodyDamage.Update sees the
    -- infected part and starts the infection on the engine's own clock.
    U().call(part, "SetBitten", true)
    if select(1, U().call(part, "bitten")) ~= true then return false end
    -- Read the bite back first: a dressing hides the bitten flag (42.21
    -- setBandaged clears it), while the bite time and infection stay.
    U().call(part, "setBandaged", true, BANDAGE_LIFE, false, "Base.RippedSheetsDirty")
    value.biteApplied = true
    return true
end

local function seedNotebook(group, actor, value)
    if value.notebookSeeded == true then return true end
    local inventory = U().inventory(actor)
    if not inventory then return false end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 120, 6)) do
        local data = U().modData(item)
        if type(data) == "table" and data.lfHershelGroupId == group.id then
            value.notebookSeeded = true
            return true
        end
    end
    local notebook = U().addItem(inventory, "Base.Notebook")
    if not notebook then return false end
    U().call(notebook, "setName", "Hershel's count")
    for index, page in ipairs(PAGES) do
        U().call(notebook, "addPage", index, page)
    end
    local data = U().modData(notebook)
    if type(data) == "table" then data.lfHershelGroupId = group.id end
    value.notebookSeeded = true
    return true
end

-- He stays down. A bitten body rises only while its ZOMBIE_INFECTION stat
-- reads 0.001 or more as it dies (42.21 shouldBecomeZombieAfterDeath, asked
-- after OnCharacterDeath fires). Clearing the infection as he dies, by mercy
-- or by anything else, lays him to rest for good.
function Bitten.layToRest(actor)
    if not actor then return false end
    local stats = select(1, U().call(actor, "getStats"))
    local stat = CharacterStat and CharacterStat.ZOMBIE_INFECTION or nil
    if stats and stat ~= nil then U().call(stats, "set", stat, 0) end
    local body = select(1, U().call(actor, "getBodyDamage"))
    U().call(body, "setInfected", false)
    local left = stats and stat ~= nil and tonumber((U().call(stats, "get", stat))) or nil
    return left ~= nil and left < 0.001
end

-- Any death of his, whatever caused it.
function Bitten.onMemberDeath(group, actor)
    local value = story(group)
    if not value then return false end
    value.stage = "dying"
    value.laidToRest = Bitten.layToRest(actor) == true
    return value.laidToRest
end

-- The engine's own progress, (now - infectionTime) / duration, measured
-- against getHoursSurvived for an IsoPlayer the way BodyDamage.Update does.
function Bitten.infectionPercent(actor)
    local body = actor and select(1, U().call(actor, "getBodyDamage"))
    if not body or select(1, U().call(body, "isInfected")) ~= true then return 0 end
    local started = tonumber((U().call(body, "getInfectionTime")))
    local duration = tonumber((U().call(body, "getInfectionMortalityDuration")))
    local current = tonumber((U().call(actor, "getHoursSurvived")))
    if not started or not duration or not current or started < 0 or duration <= 0 then
        return 0
    end
    local progress = (current - started) / duration * 100
    if progress ~= progress then return 0 end
    return math.max(0, math.min(100, progress))
end

function Bitten.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "hershel_unavailable" end
    value.actorId = U().idOf(actor)
        or group.members and group.members[1] and group.members[1].actorId
    if not applyBite(actor, value) then return false, "hershel_bite_unavailable" end
    if not seedNotebook(group, actor, value) then return false, "hershel_notebook_unavailable" end
    -- He cannot defend himself. Keep the dead off him so the player finds
    -- the man, not the meal; the infection still runs underneath.
    syncShelter(actor, not U().isDead(actor))
    return true, "hershel_on_the_floor"
end

local function near(actor, player, radius)
    return actor ~= nil and player ~= nil and U().sameFloor(actor, player)
        and U().distance(actor, player) <= radius
end

local function talkGap(value, current)
    return current + TALK_MS
        + ((tonumber(value.lines.plea) or 0) * 2741) % TALK_SPREAD_MS
end

function Bitten.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return true, "hershel_unloaded" end
    if U().isDead(actor) then return true, "hershel_dead" end
    current = tonumber(current) or U().nowMs()
    if value.stage == "dying" then return true, "hershel_dying" end
    syncShelter(actor, true)
    local close = near(actor, player, NEAR_DISTANCE) and U().canSee(actor, player) == true
    if value.stage == "waiting" then
        if close then
            value.stage = "pleading"
            value.introStep = 0
            group.discovered = true
            speak(actor, value, "greet")
            value.nextTalkAt = current + INTRO_GAP_MS
        end
        return true, value.stage
    end
    if value.stage == "pleading" and (not player
        or U().distance(actor, player) >= LEFT_DISTANCE) then
        value.stage = "left"
        value.leftAt = current
        return true, "hershel_left_alone"
    end
    if value.stage == "left" then
        if close then
            value.stage = "pleading"
            if current - (tonumber(value.leftAt) or current) >= RETURN_GRACE_MS then
                speak(actor, value, "back")
                value.nextTalkAt = talkGap(value, current)
            end
        end
        return true, value.stage
    end
    if not close then return true, "hershel_waiting_for_an_answer" end
    if value.stayLineAt and current >= value.stayLineAt then
        value.stayLineAt = nil
        speak(actor, value, "sitAfter")
        value.nextTalkAt = talkGap(value, current)
        return true, "hershel_company"
    end
    if current < (tonumber(value.nextTalkAt) or 0) then return true, "hershel_pleading" end
    local step = tonumber(value.introStep) or 2
    if step < 2 then
        value.introStep = step + 1
        speak(actor, value, "intro")
        value.nextTalkAt = step == 0 and current + INTRO_GAP_MS or talkGap(value, current)
        if step == 1 then fellowLine(group, player, "fellowMeet", "fellowMet") end
        return true, "hershel_introduced"
    end
    value.talkCount = (tonumber(value.talkCount) or 0) + 1
    local pool = "plea"
    if Bitten.infectionPercent(actor) >= LATE_INFECTION then
        pool = "late"
    elseif value.talkCount % 3 == 0 then
        pool = "fever"
    end
    speak(actor, value, pool)
    value.nextTalkAt = talkGap(value, current)
    return true, "hershel_pleading"
end

function Bitten.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "dying" or U().isDead(actor) then
        return { mode = "oddball_idle", priority = 28 }
    end
    return { mode = "bitten_floor", priority = 94 }
end

function Bitten.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "bitten_floor" then return false end
    if select(1, U().call(actor, "isSitOnGround")) == true then
        return true, "hershel_seated"
    end
    local entry = sitByActor[actor]
    if not entry then
        entry = { attempts = 0, nextAt = 0 }
        sitByActor[actor] = entry
    end
    local current = U().nowMs()
    if entry.attempts >= SIT_ATTEMPTS or current < entry.nextAt then
        return true, "hershel_too_tired_to_sit"
    end
    entry.attempts = entry.attempts + 1
    entry.nextAt = current + SIT_RETRY_MS
    local accepted = U().move(actor, "walk", { action = "sit_ground" })
    return true, accepted == true and "hershel_sitting_down" or "hershel_sit_refused"
end

function Bitten.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or not actor or U().isDead(actor) or value.stage == "dying"
        or value.stage == "waiting" or not near(actor, player, MENU_DISTANCE) then
        return {}
    end
    return {
        { id = "ask_hershel_bite", label = "Ask about the bite", enabled = true },
        { id = "ask_hershel_count", label = "Ask about the nine days", enabled = true },
        { id = "sit_with_hershel", label = "Sit with Hershel a while", enabled = true },
        { id = "refuse_hershel", label = "Tell him no", enabled = true },
        { id = "mercy_hershel", label = "Do what Hershel asks", enabled = true },
    }
end

function Bitten.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if actor and not U().isDead(actor) and value.stage ~= "dying" then
            speak(actor, value, "hurt")
        end
        -- He asked for this. No retaliation, no standing change.
        return true, "hershel_does_not_fight_back"
    end
    if not actor or U().isDead(actor) or value.stage == "dying" then
        return false, "hershel_already_gone"
    end
    if not near(actor, player, MENU_DISTANCE) then return false, "hershel_out_of_reach" end
    local current = U().nowMs()
    if value.stage == "waiting" or value.stage == "left" then value.stage = "pleading" end
    value.introStep = 2
    group.discovered = true
    if action == "ask_hershel_bite" then
        speak(actor, value, "bite")
    elseif action == "ask_hershel_count" then
        speak(actor, value, "count")
    elseif action == "sit_with_hershel" then
        speak(actor, value, "sit")
        value.stayLineAt = current + 20000
    elseif action == "refuse_hershel" then
        speak(actor, value, "refuse")
    elseif action == "mercy_hershel" then
        if not SC.Actor or type(SC.Actor.endLife) ~= "function" then
            return false, "native_life_end_unavailable"
        end
        speak(actor, value, "mercy")
        Bitten.layToRest(actor)
        local ended, reason = SC.Actor.endLife(actor)
        if ended ~= true then return false, reason or "native_life_end_refused" end
        value.stage = "dying"
        value.outcome = "mercy"
        fellowLine(group, player, "fellowMercy", "fellowSawMercy")
        return true, "hershel_mercy_granted"
    else
        return false, "unknown_hershel_choice"
    end
    value.nextTalkAt = talkGap(value, current)
    return true, action
end

function Bitten.zombiesIgnore(actor, group)
    local value = story(group)
    return value ~= nil and value.stage ~= "dying" and not U().isDead(actor)
end

function Bitten.avoidsZombieCombat()
    return true
end

function Bitten.canRecruit()
    return false, "hershel_is_not_leaving_this_floor"
end

function Bitten._resetForTests()
    sitByActor = setmetatable({}, { __mode = "k" })
end

return Bitten
