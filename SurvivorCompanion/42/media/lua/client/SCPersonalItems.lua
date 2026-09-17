-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.PersonalItems = SC.PersonalItems or {}
local PersonalItems = SC.PersonalItems

local allowedOperations = { read = true, repair = true, transactional_move = true, restore = true }
local observations = setmetatable({}, { __mode = "k" })
local keepsakeTypes = { "Base.Photo", "Base.Photo_VeryOld", "Base.Journal" }

local function U()
    return SC.GameplayUtil
end

local function cleanText(value, limit)
    value = tostring(value or "")
    value = string.gsub(value, "[%c]", "")
    if #value > (limit or 128) then value = string.sub(value, 1, limit or 128) end
    return value
end

local function nonnegative(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.max(0, value)
end

local function itemData(item)
    local data, ok = U().call(item, "getModData")
    if ok and type(data) == "table" then return data end
    return nil
end

function PersonalItems.personalRecord(item)
    local data = itemData(item)
    if not data then return nil end
    local owner = cleanText(data.SC_PersonalOwnerId, 80)
    local key = cleanText(data.SC_PersonalKey, 128)
    if owner == "" or key == "" then return nil end
    return {
        version = 1,
        ownerId = owner,
        key = key,
        kind = cleanText(data.SC_PersonalKind, 48),
    }
end

local function mark(item, personal, favorite)
    if not item or type(personal) ~= "table" then return false, "invalid_personal_item" end
    local owner = cleanText(personal.ownerId, 80)
    local key = cleanText(personal.key, 128)
    if owner == "" or key == "" then return false, "invalid_personal_marker" end
    local data = itemData(item)
    if not data then return false, "item_mod_data_unavailable" end
    local previous = {
        owner = data.SC_PersonalOwnerId,
        key = data.SC_PersonalKey,
        kind = data.SC_PersonalKind,
        version = data.SC_PersonalVersion,
    }
    local previousFavorite, previousFavoriteOk = U().call(item, "isFavorite")
    local function rollback()
        data.SC_PersonalOwnerId = previous.owner
        data.SC_PersonalKey = previous.key
        data.SC_PersonalKind = previous.kind
        data.SC_PersonalVersion = previous.version
        if previousFavoriteOk then U().call(item, "setFavorite", previousFavorite == true) end
    end
    data.SC_PersonalOwnerId = owner
    data.SC_PersonalKey = key
    data.SC_PersonalKind = cleanText(personal.kind ~= "" and personal.kind or "memento", 48)
    data.SC_PersonalVersion = 1
    if favorite ~= nil then
        local expected = favorite == true
        local _, setOk = U().call(item, "setFavorite", expected)
        if not setOk then
            rollback()
            return false, "personal_favorite_unavailable"
        end
        local retained, retainedOk = U().call(item, "isFavorite")
        if retainedOk and retained ~= expected then
            rollback()
            return false, "personal_favorite_not_retained"
        end
    end
    local verified = PersonalItems.personalRecord(item)
    if not verified or verified.ownerId ~= owner or verified.key ~= key then
        rollback()
        return false, "personal_marker_not_retained"
    end
    return true, verified
end

-- One bounded pass over a container tree. `remaining.count` is the inspection
-- budget and `remaining.skip` how many items to pass over untouched, which is
-- what lets a caller resume where the previous bounded pass stopped.
-- `remaining.exhausted` records that the budget ran out with items left, so a
-- caller can tell "not here" from "not seen yet".
local function walk(container, remaining, callback, depth, visited)
    if not container then return true end
    if remaining.count <= 0 then
        remaining.exhausted = true
        return true
    end
    visited = visited or setmetatable({}, { __mode = "k" })
    if visited[container] then return true end
    visited[container] = true
    local items, ok = U().call(container, "getItems")
    if not ok and type(container) == "table" then items = container.items or container end
    local continue = true
    local limit = remaining.count + math.max(0, remaining.skip or 0)
    U().each(items, limit, function(item)
        remaining.visited = (remaining.visited or 0) + 1
        local inspect = true
        if (remaining.skip or 0) > 0 then
            remaining.skip = remaining.skip - 1
            inspect = false
        else
            remaining.count = remaining.count - 1
        end
        if inspect and callback(item, depth or 0) == false then continue = false return false end
        local nested, nestedOk = U().call(item, "getInventory")
        if nestedOk and nested and not walk(nested, remaining, callback, (depth or 0) + 1, visited) then
            continue = false
            return false
        end
        if remaining.count <= 0 and continue then
            remaining.exhausted = true
            return false
        end
        return continue
    end)
    return continue
end

-- The same bounded recursive pass over any container, for callers that must
-- know what a corpse, bag or storage really holds before acting on it.
function PersonalItems.walkContainer(container, callback, options)
    if container == nil or type(callback) ~= "function" then return false, false end
    options = type(options) == "table" and options or {}
    local maximum = math.max(1, math.floor(tonumber(options.budget)
        or tonumber(U().config("maxInventoryItems")) or 256))
    local remaining = { count = maximum, skip = math.max(0, math.floor(tonumber(options.skip) or 0)) }
    local stopped = walk(container, remaining, callback, 0)
    return stopped, remaining.exhausted ~= true, remaining.visited or 0
end

-- Returns (stopped, complete). `complete` is false when the budget ran out
-- before the whole tree was inspected: incomplete observation is never proof
-- that something is absent.
function PersonalItems.walkActorInventory(actor, callback, options)
    if not actor or type(callback) ~= "function" then return false, false end
    options = type(options) == "table" and options or {}
    local maximum = math.max(1, math.floor(tonumber(options.budget)
        or tonumber(U().config("maxInventoryItems")) or 256))
    local remaining = { count = maximum, skip = math.max(0, math.floor(tonumber(options.skip) or 0)) }
    local stopped = walk(U().inventory(actor), remaining, callback, 0)
    return stopped, remaining.exhausted ~= true, remaining.visited or 0
end

-- A resumable search over one actor's whole inventory tree. Each call inspects
-- at most `budget` items starting at `cursor`; the caller keeps the returned
-- cursor. Status is "found", "absent" (the tree ended) or "pending" (more to
-- look at). Bags are entered, so nothing hides behind a full first bag.
function PersonalItems.searchResumable(actor, predicate, cursor, budget)
    if not actor or type(predicate) ~= "function" then return nil, 0, "absent" end
    local found, foundDepth
    local _, complete = PersonalItems.walkActorInventory(actor, function(item, depth)
        if predicate(item, depth) then
            found, foundDepth = item, depth
            return false
        end
    end, { budget = budget, skip = cursor })
    if found then return found, math.max(0, math.floor(tonumber(cursor) or 0)), "found", foundDepth end
    if complete then return nil, 0, "absent" end
    local inspected = math.max(1, math.floor(tonumber(budget)
        or tonumber(U().config("maxInventoryItems")) or 256))
    return nil, math.max(0, math.floor(tonumber(cursor) or 0)) + inspected, "pending"
end

-- Is this exact item still inside the actor's inventory tree, including bags?
-- Returns true, false, or nil when the native owner chain cannot be read.
function PersonalItems.ownedBy(item, actor)
    if item == nil or actor == nil then return false end
    local root = U().inventory(actor)
    if root == nil then return nil end
    local container, ok = U().call(item, "getContainer")
    if not ok then return nil end
    for _ = 1, 8 do
        if container == nil then return false end
        if container == root then return true end
        local parent, parentOk = U().call(container, "getParent")
        if parentOk and parent ~= nil and parent == actor then return true end
        local holder, holderOk = U().call(container, "getContainingItem")
        if not holderOk or holder == nil then return false end
        container, ok = U().call(holder, "getContainer")
        if not ok then return nil end
    end
    return nil
end

function PersonalItems.find(actor, key)
    local found, foundDepth
    PersonalItems.walkActorInventory(actor, function(item, depth)
        local personal = PersonalItems.personalRecord(item)
        if personal and (key == nil or personal.key == key) then
            found, foundDepth = item, depth
            return false
        end
    end)
    return found, foundDepth
end

local function isMemento(item)
    local value, ok = U().call(item, "isMemento")
    if ok and value == true then return true end
    local category, categoryOk = U().call(item, "getDisplayCategory")
    if categoryOk and string.lower(tostring(category)) == "memento" then return true end
    local normalCategory, normalOk = U().call(item, "getCategory")
    if normalOk and string.lower(tostring(normalCategory)) == "memento" then return true end
    return U().itemHasTag(item, "IsMemento") or U().itemHasTag(item, "ismemento")
        or U().itemHasTag(item, "base:ismemento")
end

local function kindOf(item)
    local itemType = string.lower(U().itemType(item))
    if string.find(itemType, "photo", 1, true) then return "photo" end
    if string.find(itemType, "locket", 1, true) then return "locket" end
    if string.find(itemType, "watch", 1, true) then return "watch" end
    if string.find(itemType, "journal", 1, true) or string.find(itemType, "notebook", 1, true) then
        return "journal"
    end
    return "memento"
end

local function copyKeepsake(source)
    if type(source) ~= "table" then return nil end
    local result = {
        version = 1,
        ownerId = cleanText(source.ownerId, 80),
        key = cleanText(source.key, 128),
        kind = cleanText(source.kind, 48),
        itemType = cleanText(source.itemType, 128),
        status = source.status == "carried" and "carried" or "not_carried",
        revealed = source.revealed == true,
        assignedAt = nonnegative(source.assignedAt),
        lastSeenAt = nonnegative(source.lastSeenAt),
    }
    if type(source.nestedCarried) == "table" then result.nestedCarried = source.nestedCarried end
    return result
end

function PersonalItems.normalize(source)
    source = type(source) == "table" and source or {}
    return { version = 1, keepsake = copyKeepsake(source.keepsake) }
end

function PersonalItems.ensure(actor, source)
    local possessions = PersonalItems.normalize(source)
    local id = U().idOf(actor)
    if type(id) ~= "string" or id == "" then return nil, "companion_id_unavailable" end
    local keepsake = possessions.keepsake
    if keepsake and keepsake.key ~= "" then
        local item = PersonalItems.find(actor, keepsake.key)
        if item then
            keepsake.status = "carried"
            keepsake.lastSeenAt = U().nowMs()
            keepsake.itemType = U().itemType(item)
        else
            keepsake.status = "not_carried"
        end
        return possessions, "personal_item_normalized"
    end

    local selected
    PersonalItems.walkActorInventory(actor, function(item)
        if not PersonalItems.personalRecord(item) and isMemento(item) then selected = item return false end
    end)
    local created = false
    local creationReason = "no keepsake type was attempted"
    if not selected then
        local inventory = U().inventory(actor)
        for _, itemType in ipairs(keepsakeTypes) do
            selected, creationReason = U().addItem(inventory, itemType)
            if selected then
                created = true
                break
            end
        end
        -- A keepsake adds character depth but is not part of the native actor
        -- safety contract. Never roll back a healthy companion because an item
        -- script or another inventory mod rejected this optional assignment.
        if not selected then
            return possessions, "personal_item_deferred:" .. cleanText(creationReason, 120)
        end
    end
    local personal = {
        version = 1,
        ownerId = id,
        key = id .. ":keepsake:1",
        kind = kindOf(selected),
    }
    local marked, marker = mark(selected, personal, true)
    if not marked then
        if created then U().call(U().inventory(actor), "Remove", selected) end
        return possessions, "personal_item_deferred:" .. cleanText(marker, 120)
    end
    local now = U().nowMs()
    possessions.keepsake = {
        version = 1,
        ownerId = id,
        key = personal.key,
        kind = personal.kind,
        itemType = U().itemType(selected),
        status = "carried",
        revealed = false,
        assignedAt = now,
        lastSeenAt = now,
    }
    return possessions, "personal_item_assigned"
end

function PersonalItems.observe(actor, source, force)
    local current = U().nowMs()
    local interval = U().config("objectiveAuditIntervalMs") or 5000
    if force ~= true and actor and current < (observations[actor] or 0) then
        return source, false
    end
    if actor then observations[actor] = current + interval end
    local possessions = PersonalItems.normalize(source)
    local keepsake = possessions.keepsake
    if not keepsake or keepsake.key == "" then return possessions, false end
    local item = PersonalItems.find(actor, keepsake.key)
    local status = item and "carried" or "not_carried"
    local changed = status ~= keepsake.status
    keepsake.status = status
    if item then
        keepsake.lastSeenAt = U().nowMs()
        keepsake.itemType = U().itemType(item)
    end
    return possessions, changed, item
end

function PersonalItems.reset(actor)
    if actor then observations[actor] = nil
    else observations = setmetatable({}, { __mode = "k" }) end
end

function PersonalItems.isProtected(item, actorOrId, operation)
    if SC.WorkTransport and type(SC.WorkTransport.isCargoProtected) == "function"
        and SC.WorkTransport.isCargoProtected(item, actorOrId, operation) then
        return true
    end
    local personal = PersonalItems.personalRecord(item)
    if not personal then return false end
    if allowedOperations[operation] then return false end
    local requester = type(actorOrId) == "string" and actorOrId or U().idOf(actorOrId)
    if operation == "return_to_owner" and requester == personal.ownerId then return false end
    return true
end

function PersonalItems.restoreMarker(item, personal, favorite)
    return mark(item, personal, favorite)
end

function PersonalItems.findNested(actor, ownerId, key)
    local found, personal
    PersonalItems.walkActorInventory(actor, function(item, depth)
        local candidate = PersonalItems.personalRecord(item)
        if depth > 0 and candidate and candidate.ownerId == ownerId
            and (key == nil or candidate.key == key) then
            found, personal = item, candidate
            return false
        end
    end)
    return found, personal
end

function PersonalItems.description(source, revealed)
    local keepsake = type(source) == "table" and source.keepsake or nil
    if type(keepsake) ~= "table" then
        return { known = false, status = "unknown", kind = "unknown", itemType = nil }
    end
    if revealed ~= true and keepsake.revealed ~= true then
        return { known = false, status = "unknown", kind = "private", itemType = nil }
    end
    return {
        known = true,
        status = keepsake.status == "carried" and "carried" or "not_carried",
        kind = keepsake.kind ~= "" and keepsake.kind or "memento",
        itemType = keepsake.itemType ~= "" and keepsake.itemType or nil,
    }
end

return PersonalItems
