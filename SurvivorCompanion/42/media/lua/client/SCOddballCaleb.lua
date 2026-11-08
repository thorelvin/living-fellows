-- SPDX-License-Identifier: MIT
-- A bereaved stranger gathers his family. Fire and death remain native;
-- this scene never deducts health or turns a timer into a scripted kill.
local SC = SurvivorCompanion
SC.OddballCaleb = SC.OddballCaleb or {}
local Caleb = SC.OddballCaleb
local ID = "family_pyre_caleb_hensley"
local TAG, SLOT = "LF_FamilyPyre", "LF_FamilyPyreSlot"
local TALE = {
    "Caleb Hensley. Those are my people. Please don't take anything from them.",
    "Martha kept the curtains shut. My brother brought the radio. Dad said it would pass.",
    "When they stopped answering, I waited outside. I thought waiting was helping.",
    "I brought them out one at a time. Dad was still wearing his good shoes.",
    "I can't leave them scattered round this place. Let me get them together.",
}
local SOURCES = { { -3, 0 }, { 0, -3 }, { 3, 0 } }
local function U() return SC.GameplayUtil end
local function story(group)
    local value = group and group.oddball
    return type(value) == "table" and value.id == ID and value or nil
end
local function square(post)
    return post and U().gridSquare(post.x, post.y, post.z or 0) or nil
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end
local function close(actor, player, radius)
    return actor and player and U().sameFloor(actor, player)
        and U().distance(actor, player) <= radius and U().canSee(player, actor) == true
end
local function dragging(actor)
    return SC.NativeActions and SC.NativeActions.isDraggingCorpse(actor) == true
end
local function release(actor)
    if SC.NativeActions then
        SC.NativeActions.releaseCorpse(actor)
        SC.NativeActions.settleDrag(actor)
    end
end
local function outdoor(tile)
    return tile and select(1, U().call(tile, "isOutside")) == true
        and select(1, U().call(tile, "getRoom")) == nil
        and select(1, U().call(tile, "getBuilding")) == nil
        and select(1, U().call(tile, "getTree")) == nil
        and not (SC.BaseLife and SC.BaseLife.isInside(tile))
end

-- A small open clearing, away from buildings and marked camp. Every inspected
-- tile is loaded; discovery uses the existing bounded Strange Folk survey.
function Caleb.siteFor(tile, player, allowSeen)
    local x, y, z = U().position(tile)
    if not x or z ~= 0 or not outdoor(tile) then return nil end
    x, y = math.floor(x), math.floor(y)
    if not allowSeen and (not player or U().canSee(player, tile) == true) then return nil end
    for dx = -4, 4 do
        for dy = -4, 4 do
            local candidate = U().gridSquare(x + dx, y + dy, 0)
            if not outdoor(candidate) or not U().isClearActorSpawnSquare(candidate) then return nil end
            if not allowSeen and U().canSee(player, candidate) == true then return nil end
        end
    end
    local posts = {}
    for index, offset in ipairs(SOURCES) do
        local post = { x = x + offset[1], y = y + offset[2], z = 0 }
        if not outdoor(square(post)) or not U().isClearActorSpawnSquare(square(post)) then return nil end
        posts[index] = post
    end
    local anchor, stand = { x = x, y = y, z = 0 }, { x = x - 2, y = y, z = 0 }
    return { kind = "family_pyre", room = "clearing", anchor = anchor,
        spawn = stand, familySpawns = posts,
        house = { id = "family-pyre:" .. x .. ":" .. y, anchor = anchor,
            bounds = { x1 = x - 4, x2 = x + 4, y1 = y - 4, y2 = y + 4 },
            interior = { stand }, openings = {} } }
end

local function owned(body, group, slot)
    local data = body and U().modData(body)
    return data and data[TAG] == group.id and data[SLOT] == slot
end
local function bodyOn(tile, group, slot)
    local found
    if tile then U().squareStaticMovingObjects(tile, function(body)
        if U().instanceOf(body, "IsoDeadBody") and owned(body, group, slot) then
            found = body
            return false
        end
    end, 24) end
    return found
end
local function findBody(group, slot)
    local value = story(group)
    local anchor = value.site.anchor
    -- A release can leave the body between its source and the pile. Search
    -- that small authored clearing, never the cell or unrelated corpses.
    local source = value.site.familySpawns[slot]
    local found = bodyOn(square(source), group, slot)
    if found then return found end
    local receipt = value.familyReceipts and value.familyReceipts[slot]
    if type(receipt) == "table" then
        found = bodyOn(square(receipt), group, slot)
        if found then return found end
    end
    for dx = -1, 1 do
        for dy = -1, 1 do
            found = bodyOn(U().gridSquare(anchor.x + dx, anchor.y + dy, anchor.z or 0), group, slot)
            if found then return found end
        end
    end
    for dx = -4, 4 do
        for dy = -4, 4 do
            found = bodyOn(U().gridSquare(anchor.x + dx, anchor.y + dy, anchor.z or 0), group, slot)
            if found then return found end
        end
    end
end
local function remember(group, slot, body)
    local x, y, z = U().position(body)
    if x then story(group).familyReceipts[slot] = {
        x = math.floor(x), y = math.floor(y), z = math.floor(z), verified = true } end
end
local function inPile(body, value)
    local x, y, z = U().position(body)
    local p = value.site.anchor
    return x and z == (p.z or 0) and math.abs(x - p.x - 0.5) <= 1.5
        and math.abs(y - p.y - 0.5) <= 1.5
end
local function familyReady(group)
    local value = story(group)
    for slot = 1, 3 do
        if not inPile(findBody(group, slot), value) then return false end
    end
    return true
end
local function issue(group, reason)
    local value = story(group)
    value.problem = reason
    value.retryAt = U().nowMs() + 5000
    return true, reason
end
local function finishWork(actor)
    local native = SC.NativeActions
    if not native then return false end
    if native.isWorkActive(actor) then return false end
    return native.finishWork(actor) == true
end
local function walk(actor, post, action, drag)
    local target = square(post)
    if not target then return false, "scene_square_unloaded" end
    return SC.Navigation.request(actor, target, "walk", {
        action = action, arrivalDistance = drag and 0.35 or 0.2,
        requireSameSquare = true, draggingBody = drag == true,
    })
end
local function travel(group, actor, post, action, drag)
    local accepted, reason = walk(actor, post, action, drag)
    story(group).movementReason = reason
    if accepted ~= true then return issue(group, reason or "scene_route_blocked") end
    return true, reason
end

function Caleb.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "caleb_unavailable" end
    if value.stage == nil or value.stage == "unmet" then value.stage = "gathering" end
    value.familyReceipts = value.familyReceipts or {}
    if value.stage == "dead" or value.stage == "interrupted" or value.stage == "burning" then return true end
    if type(value.site.familySpawns) ~= "table" or #value.site.familySpawns ~= 3 then
        return false, "family_site_invalid"
    end
    if not value.appearanceApplied then
        local enum = BloodBodyPartType
        if enum then
            U().call(actor, "addHole", enum.UpperArm_L, true)
            U().call(actor, "addHole", enum.LowerLeg_R, true)
        end
        U().call(actor, "resetModelNextFrame")
        value.appearanceApplied = true
    end
    for slot, post in ipairs(value.site.familySpawns or {}) do
        if not value.familyReceipts[slot] then
            local tile = square(post)
            if not tile or type(createRandomDeadBody) ~= "function" then
                return false, "family_source_unloaded"
            end
            -- Commit before the native effect. Ambiguous interrupted creation
            -- must never duplicate a corpse or its inventory after reloading.
            value.familyReceipts[slot] = { x = post.x, y = post.y, z = post.z }
            local okay, body = pcall(createRandomDeadBody, tile, 0)
            local data = okay and body and U().modData(body)
            if not data then return false, "family_body_unverified" end
            data[TAG], data[SLOT] = group.id, slot
            U().call(body, "setReanimateTime", -1)
            remember(group, slot, body)
        elseif not findBody(group, slot) then
            local target = select(1, U().call(actor, "getGrapplingTarget"))
            if not owned(target, group, slot) then return false, "family_body_missing" end
        end
    end
    return true, "family_scene_ready"
end

function Caleb.pulse(group, player, current)
    local value, actor = story(group), actorFor(group)
    if not value or not actor then return true, "caleb_unloaded" end
    if U().isDead(actor) then Caleb.onMemberDeath(group, actor); return true, "caleb_dead" end
    if value.stage == "dead" or value.stage == "interrupted" then return true, value.stage end
    if value.stage == "burning" and select(1, U().call(actor, "isOnFire")) == false
        and select(1, U().call(square(value.site.anchor), "haveFire")) == false then
        -- The engine may briefly extinguish clothing while the ground is
        -- still burning, then ignite it again through normal fire contact.
        value.stage, value.outcome = "interrupted", "fire_extinguished"
        return true, value.stage
    end
    if not value.met and close(actor, player, 8) then
        if SC.NativeActions then
            local cancelled = SC.NativeActions.cancelWork(actor, "family_story_pause")
            if cancelled ~= true then return issue(group, "family_work_busy") end
        end
        value.met, value.stage, value.taleStep = true, "telling", 1
        value.nextLineAt = current + 6500
        group.discovered = true
        release(actor)
        value.workPhase = nil
        U().say(actor, TALE[1])
    elseif value.stage == "telling" and close(actor, player, 12)
        and current >= (value.nextLineAt or 0) then
        value.taleStep = (value.taleStep or 1) + 1
        local line = TALE[value.taleStep]
        if line then
            U().say(actor, line)
            value.nextLineAt = current + 6500
        else
            value.taleFinished, value.stage, value.workPhase = true, "gathering", nil
        end
    elseif value.stage == "farewell" and current >= (value.fireAt or current)
        and current >= (value.retryAt or 0) and close(actor, player, 18) then
        if not familyReady(group) then value.stage = "gathering"; return true, "pile_changed" end
        local center = square(value.site.anchor)
        if not center or not outdoor(center) then return issue(group, "pyre_square_blocked") end
        if not value.fireAttempted then
            if not IsoFireManager or type(getCell) ~= "function" then
                return issue(group, "native_fire_unavailable")
            end
            value.fireAttempted = true
            local okay = pcall(IsoFireManager.StartFire, getCell(), center, true, 100, 500)
            if not okay then return issue(group, "native_fire_failed") end
        end
        if select(1, U().call(center, "haveFire")) ~= true then
            return issue(group, "native_fire_unverified")
        end
        U().call(actor, "SetOnFire")
        if select(1, U().call(actor, "isOnFire")) == true then
            value.stage, value.problem = "burning", nil
        end
    end
    -- Burning has no damage script and no death deadline. The engine owns
    -- fire damage, extinguishing, death, and the resulting real corpse.
    return true, value.stage
end

function Caleb.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value or value.stage == "dead" or value.stage == "interrupted" then return nil end
    return { mode = "family_pyre_scene", priority = 130 }
end

function Caleb.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent or intent.mode ~= "family_pyre_scene" then return false end
    local current = U().nowMs()
    if value.stage == "telling" then
        if dragging(actor) then release(actor) else U().stop(actor) end
        return true, "telling_family_story"
    end
    if value.stage == "farewell" or value.stage == "burning" then
        U().stop(actor)
        return true, value.stage
    end
    if value.stage ~= "gathering" or current < (value.retryAt or 0) then return true, value.stage end
    local native = SC.NativeActions
    if not native or not SC.Navigation then return issue(group, "corpse_work_unavailable") end
    if (value.workPhase == "grabbing" or value.workPhase == "dropping")
        and current - (value.workAt or current) > 15000 then
        if native.cancelWork(actor, "family_work_timeout") == true then value.workPhase = nil end
        return issue(group, "family_work_timeout")
    end
    if value.workPhase == "grabbing" then
        if not finishWork(actor) then return true, "gathering_family" end
        if dragging(actor) then
            value.workPhase, value.grabConfirmedAt = "dragging", current
            value.problem, value.retryAt = nil, nil
            return true, "taking_hold_of_family"
        elseif current - (value.workAt or current) > 8000 then
            value.workPhase = nil
            return issue(group, "family_grab_unverified")
        else return true, "waiting_for_grapple" end
    end
    if value.workPhase == "dropping" then
        if not finishWork(actor) or dragging(actor) then return true, "placing_family" end
        native.settleDrag(actor)
        local body = findBody(group, value.activeSlot)
        value.workPhase = nil
        if not inPile(body, value) then return issue(group, "family_drop_unverified") end
        value.problem, value.retryAt = nil, nil
    end
    if dragging(actor) then
        -- Recover a saved drag only when its native target carries our tag.
        local target = select(1, U().call(actor, "getGrapplingTarget"))
        local data = target and U().modData(target)
        local slot = data and data[SLOT]
        if not data or data[TAG] ~= group.id or (slot ~= 1 and slot ~= 2 and slot ~= 3) then
            release(actor)
            return issue(group, "foreign_drag")
        end
        value.activeSlot = slot
        remember(group, slot, target)
        -- The timed action completes before the paired pickup pose releases
        -- its movement lock. Do not send navigation's stop/recovery through
        -- that short native transition or it drops the new grapple.
        if U().movementStateBlocker and U().movementStateBlocker(actor) then
            if current - (value.grabConfirmedAt or current) > 15000 then
                release(actor)
                return issue(group, "family_grapple_blocked")
            end
            return true, "finishing_family_grab"
        end
        if inPile(target, value) then
            local accepted, reason = U().move(actor, "walk", {
                action = "drop_body", targetSquare = U().squareOf(actor),
            })
            if accepted then value.workPhase, value.workAt = "dropping", current
            else return issue(group, reason or "family_drop_blocked") end
        else
            local accepted, reason = walk(actor, value.site.anchor, "gather_family", true)
            value.movementReason = reason
            if accepted ~= true then return issue(group, reason or "family_drag_blocked") end
        end
        return true, "gathering_family"
    end
    for slot = 1, 3 do
        local body = findBody(group, slot)
        if not body then return issue(group, "family_body_missing") end
        remember(group, slot, body)
        if not inPile(body, value) then
            if U().distance(actor, body) > 0.9 then
                local x, y, z = U().position(body)
                return travel(group, actor, { x = math.floor(x), y = math.floor(y), z = z },
                    "approach_family", false)
            end
            if SC.Navigation.cancel then SC.Navigation.cancel(actor, "family_pickup") end
            local accepted, reason = U().move(actor, "walk", {
                action = "grab_body", body = body, targetSquare = U().squareOf(body),
            })
            if accepted then
                value.activeSlot, value.workPhase, value.workAt = slot, "grabbing", current
            else return issue(group, reason or "family_grab_blocked") end
            return true, "gathering_family"
        end
    end
    if not value.taleFinished then U().stop(actor); return true, "waiting_to_talk" end
    if not close(actor, player, 18) then return true, "waiting_for_witness" end
    local center = square(value.site.anchor)
    local ax, ay = U().position(actor)
    local anchor = value.site.anchor
    if not center or not ax then return issue(group, "pyre_square_unloaded") end
    if (ax - anchor.x - 0.5)^2 + (ay - anchor.y - 0.5)^2 > 0.12 then
        return travel(group, actor, anchor, "stand_with_family", false)
    end
    U().stop(actor)
    value.stage, value.fireAt, value.problem = "farewell", current + 4000, nil
    U().say(actor, "I WILL JOIN YOU IN DEATH!")
    return true, "family_farewell"
end

function Caleb.menuOptions(group, player)
    local value, actor = story(group), actorFor(group)
    if not value or not close(actor, player, 4) or U().isDead(actor)
        or value.stage == "farewell" or value.stage == "burning" then return {} end
    return { { id = "listen_caleb", label = "Listen to Caleb", enabled = true } }
end
function Caleb.action(group, action, player)
    local value, actor = story(group), actorFor(group)
    if not value or not actor or U().isDead(actor) then return false, "caleb_unavailable" end
    if action ~= "listen_caleb" or not close(actor, player, 4)
        or value.stage == "farewell" or value.stage == "burning" then return false, "caleb_unavailable" end
    if not value.met then return Caleb.pulse(group, player, U().nowMs()) end
    return true, "caleb_story_in_progress"
end
function Caleb.canRecruit() return false, "caleb_stays_with_his_family" end
function Caleb.ownsCorpseDrag(actor, group)
    local value = story(group)
    local slot = value and value.activeSlot
    if not value or value.stage ~= "gathering" or (slot ~= 1 and slot ~= 2 and slot ~= 3) then return false end
    local target = select(1, U().call(actor, "getGrapplingTarget"))
    if target then return owned(target, group, slot) == true end
    return (value.workPhase == "grabbing" or value.workPhase == "dropping")
        and SC.NativeActions and SC.NativeActions.dragSessionActive(actor) == true or false
end
function Caleb.zombiesIgnore(actor, group)
    local value = story(group)
    return value ~= nil and value.stage ~= "dead" and value.stage ~= "interrupted"
end
function Caleb.avoidsZombieCombat() return true end
function Caleb.onMemberDeath(group, actor)
    local value = story(group)
    if value and U().isDead(actor) then
        value.outcome = value.stage == "burning" and "died_in_fire" or "interrupted"
        value.stage, value.workPhase = "dead", nil
    end
end
return Caleb
