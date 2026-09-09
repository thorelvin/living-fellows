-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.BaseObjectRef = SC.BaseObjectRef or {}
local BaseObjectRef = SC.BaseObjectRef

BaseObjectRef.OBJECT_ID_KEY = "LF_BaseObjectId"

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function integer(value, fallback)
    return math.floor(finite(value, fallback or 0))
end

local function cleanText(value, fallback, maximum)
    local result = type(value) == "string" and value or tostring(value or "")
    result = string.gsub(result, "[%c]", "")
    if result == "" then result = fallback or "" end
    maximum = maximum or 64
    if #result > maximum then result = string.sub(result, 1, maximum) end
    return result
end

local function validId(value)
    return type(value) == "string" and #value >= 3 and #value <= 96
        and string.sub(value, 1, 7) == "object:"
end

local function utilityFor(context)
    return type(context) == "table" and context.utility or SC.GameplayUtil
end

local function position(value, utility)
    if type(value) == "table" and finite(value.x, nil) ~= nil
        and finite(value.y, nil) ~= nil then
        return {
            x = integer(value.x, 0), y = integer(value.y, 0), z = integer(value.z, 0),
        }
    end
    if not utility or not value then return nil end
    local x, y, z = utility.position(value)
    if x == nil or y == nil then
        local square = utility.squareOf(value)
        x, y, z = utility.position(square)
    end
    if x == nil or y == nil then return nil end
    return { x = integer(x, 0), y = integer(y, 0), z = integer(z, 0) }
end

function BaseObjectRef.validId(value)
    return validId(value)
end

function BaseObjectRef.signature(object, context)
    local utility = utilityFor(context)
    if not utility or not object then return nil end
    local objectName, objectNameOk = utility.call(object, "getObjectName")
    local sprite, spriteOk = utility.call(object, "getSprite")
    local spriteName, spriteNameOk = spriteOk and utility.call(sprite, "getName") or nil, false
    if spriteOk then spriteName, spriteNameOk = utility.call(sprite, "getName") end
    local container, containerOk = utility.call(object, "getContainer")
    local containerType, containerTypeOk = containerOk
        and utility.call(container, "getType") or nil, false
    if containerOk then containerType, containerTypeOk = utility.call(container, "getType") end
    return cleanText(table.concat({
        objectNameOk and tostring(objectName) or "",
        spriteNameOk and tostring(spriteName) or "",
        containerTypeOk and tostring(containerType) or "",
    }, "|"), "||", 192)
end

function BaseObjectRef.identity(object, context, create)
    local utility = utilityFor(context)
    local modData, ok = utility and utility.call(object, "getModData") or nil, false
    if utility then modData, ok = utility.call(object, "getModData") end
    if not ok or type(modData) ~= "table" then
        return nil, "object_mod_data_unavailable"
    end
    local objectId = modData[BaseObjectRef.OBJECT_ID_KEY]
    if validId(objectId) then return objectId end
    if create ~= true then return nil, "object_identity_missing" end
    local allocator = type(context) == "table" and context.allocateId or nil
    if type(allocator) ~= "function" then return nil, "object_identity_allocator_unavailable" end
    objectId = allocator()
    if not validId(objectId) then return nil, "object_identity_allocation_failed" end
    modData[BaseObjectRef.OBJECT_ID_KEY] = objectId
    -- Single-player mutates the authoritative object immediately; multiplayer
    -- builds that expose transmission also receive the persistent identity.
    utility.call(object, "transmitModData")
    return objectId
end

function BaseObjectRef.describe(object, context)
    local utility = utilityFor(context)
    local point = position(object, utility)
    local index, ok
    if utility then index, ok = utility.call(object, "getObjectIndex") end
    if not point or not ok or finite(index, nil) == nil or tonumber(index) < 0 then
        return nil
    end
    local objectId, identityReason = BaseObjectRef.identity(
        object, context, type(context) == "table" and context.createIdentity == true)
    if not objectId then return nil, identityReason end
    return {
        x = point.x, y = point.y, z = point.z, objectIndex = integer(index, -1),
        objectId = objectId, objectSignature = BaseObjectRef.signature(object, context),
    }
end

function BaseObjectRef.copy(reference, target)
    if type(reference) ~= "table" then return nil, "invalid_object_record" end
    target = type(target) == "table" and target or {}
    target.x, target.y, target.z = reference.x, reference.y, reference.z
    target.objectIndex = reference.objectIndex
    target.objectId = reference.objectId
    target.objectSignature = reference.objectSignature
    return target
end

function BaseObjectRef.normalize(reference)
    if type(reference) ~= "table" then return nil end
    local point = position(reference, nil)
    local objectIndex = integer(reference.objectIndex, -1)
    if not point or objectIndex < 0 then return nil end
    return {
        x = point.x, y = point.y, z = point.z, objectIndex = objectIndex,
        objectId = validId(reference.objectId) and reference.objectId or nil,
        objectSignature = type(reference.objectSignature) == "string"
            and cleanText(reference.objectSignature, "", 192) or nil,
    }
end

function BaseObjectRef.resolve(reference, context)
    if type(reference) ~= "table" then return nil, "invalid_object_record" end
    if not validId(reference.objectId) then
        -- Coordinates and a mutable square-list index are not identity. Existing
        -- saves remain readable, but require one explicit re-registration instead
        -- of silently binding camp work to whichever object moved into the slot.
        return nil, "legacy_object_identity_unavailable"
    end
    local utility = utilityFor(context)
    local square = utility and utility.gridSquare(reference.x, reference.y, reference.z) or nil
    if not square then return nil, "object_square_unloaded" end
    local found, matches = nil, 0
    utility.squareObjects(square, function(object)
        local objectId = BaseObjectRef.identity(object, context, false)
        if objectId == reference.objectId then
            matches = matches + 1
            found = object
        end
    end, 64)
    if matches == 1 then return found end
    if matches > 1 then return nil, "ambiguous_object_identity" end
    return nil, "object_identity_mismatch"
end

return BaseObjectRef
