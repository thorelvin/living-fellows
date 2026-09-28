-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then
    pcall(require, "SCGameplayUtil")
end

SC.InventoryIndex = SC.InventoryIndex or {}
local Index = SC.InventoryIndex
local entries, versions = {}, {}
local MAX_AGE_MS = 250

local function U()
    return SC.GameplayUtil
end

local function shortType(itemType)
    if itemType == nil then return nil end
    local value = tostring(itemType)
    if value == "" then return nil end
    return string.match(value, "%.([%w_]+)$") or value
end

local function contentsFingerprint(container)
    local utility = U()
    local items = select(1, utility.call(container, "getItems"))
    if items == nil and type(container) == "table" then
        items = container.items or container
    end
    local weight = select(1, utility.call(container, "getContentsWeight"))
    return utility.listSize(items), tonumber(weight)
end

local function sameFingerprint(entry, inventory, primary, secondary)
    if entry.inventory ~= inventory or entry.primary ~= primary
        or entry.secondary ~= secondary then return false end
    local count, weight = contentsFingerprint(inventory)
    if entry.count ~= count or entry.weight ~= weight then return false end
    for _, nested in ipairs(entry.nested or {}) do
        local nestedCount, nestedWeight = contentsFingerprint(nested.container)
        if nested.count ~= nestedCount or nested.weight ~= nestedWeight then
            return false
        end
    end
    return true
end

local function isWeaponCandidate(item)
    local utility = U()
    local hasData, dataOk = utility.call(item, "hasModData")
    if (not dataOk or hasData == true) and SC.PersonalItems
        and type(SC.PersonalItems.personalRecord) == "function" then
        local personal = SC.PersonalItems.personalRecord(item)
        if personal and personal.kind == "writing_implement" then return false end
    end
    local category = select(1, utility.call(item, "getCategory"))
    return utility.instanceOf(item, "HandWeapon")
        or utility.instanceOf(item, "zombie.inventory.types.HandWeapon")
        or (tostring(category or "") == "Weapon"
            and utility.hasMethod(item, "getMaxDamage"))
end

local function rebuild(actor, inventory, primary, secondary, current)
    local utility = U()
    local limit = utility.config("combatInventoryScanLimit") or 240
    local items, containers = utility.inventoryItemsDeep(inventory, limit)
    local entry = {
        actor = actor, inventory = inventory, primary = primary,
        secondary = secondary, version = versions[actor] or 0,
        expiresAt = current + MAX_AGE_MS,
        weapons = {}, magazinesByType = {}, looseAmmoByType = {},
        itemsByType = {}, itemCountByType = {},
        itemSet = {}, nested = {}, nestedSet = {},
    }
    entry.count, entry.weight = contentsFingerprint(inventory)
    for _, container in ipairs(containers or {}) do
        local count, weight = contentsFingerprint(container)
        entry.nested[#entry.nested + 1] = {
            container = container, count = count, weight = weight,
        }
        entry.nestedSet[container] = true
    end
    for _, item in ipairs(items or {}) do
        entry.itemSet[item] = true
        local key = shortType(utility.itemType(item))
        if key ~= nil then
            local typed = entry.itemsByType[key]
            if typed == nil then
                typed = {}
                entry.itemsByType[key] = typed
            end
            typed[#typed + 1] = item
            entry.itemCountByType[key] = (entry.itemCountByType[key] or 0) + 1
        end
        if isWeaponCandidate(item) then
            entry.weapons[#entry.weapons + 1] = item
        elseif key ~= nil then
            local maxAmmoValue = select(1, utility.call(item, "getMaxAmmo"))
            local maxAmmo = tonumber(maxAmmoValue) or 0
            if maxAmmo > 0 then
                local magazines = entry.magazinesByType[key]
                if magazines == nil then
                    magazines = {}
                    entry.magazinesByType[key] = magazines
                end
                magazines[#magazines + 1] = item
            else
                entry.looseAmmoByType[key] =
                    (entry.looseAmmoByType[key] or 0) + 1
            end
        end
    end
    return entry
end

function Index.get(actor)
    if actor == nil then return nil end
    local utility = U()
    if utility == nil then return nil end
    local inventory = utility.inventory(actor)
    if inventory == nil then return nil end
    local primary = select(1, utility.call(actor, "getPrimaryHandItem"))
    local secondary = select(1, utility.call(actor, "getSecondaryHandItem"))
    local current = utility.nowMs()
    local entry = entries[actor]
    if entry ~= nil and entry.version == (versions[actor] or 0)
        and current < entry.expiresAt
        and sameFingerprint(entry, inventory, primary, secondary) then
        entry.hits = (entry.hits or 0) + 1
        if SC.Performance then SC.Performance.count("inventory.index.hit") end
        return entry
    end
    if SC.Performance then
        SC.Performance.count("inventory.index.build")
        if entry ~= nil then
            if entry.version ~= (versions[actor] or 0) then
                SC.Performance.count("inventory.index.touched")
            elseif current >= entry.expiresAt then
                SC.Performance.count("inventory.index.expired")
            else
                SC.Performance.count("inventory.index.fingerprint-change")
            end
        end
    end
    local built = rebuild(actor, inventory, primary, secondary, current)
    built.builds = (entry and entry.builds or 0) + 1
    entries[actor] = built
    return built
end

function Index.forInventory(inventory)
    if inventory == nil then return nil end
    for actor, entry in pairs(entries) do
        if entry.inventory == inventory then return Index.get(actor) end
    end
    return nil
end

function Index.touch(actor)
    if actor == nil then return false end
    versions[actor] = (versions[actor] or 0) + 1
    return true
end

function Index.touchContainer(container)
    if container == nil then return false end
    local touched = false
    for actor, entry in pairs(entries) do
        if entry.inventory == container or entry.nestedSet[container] then
            Index.touch(actor)
            touched = true
        end
    end
    return touched
end

function Index.touchItem(item)
    if item == nil then return false end
    local touched = false
    for actor, entry in pairs(entries) do
        if entry.itemSet[item] then
            Index.touch(actor)
            touched = true
        end
    end
    return touched
end

function Index.release(actor)
    if actor == nil then return false end
    entries[actor], versions[actor] = nil, nil
    return true
end

function Index.reset()
    entries, versions = {}, {}
end

return Index
