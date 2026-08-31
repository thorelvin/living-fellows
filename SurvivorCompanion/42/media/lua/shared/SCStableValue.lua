-- SPDX-License-Identifier: MIT

if type(require) == "function" then pcall(require, "SCNamespace") end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.StableValue = SC.StableValue or {}

local StableValue = SC.StableValue

local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

function StableValue.copyStrict(value, options)
    options = type(options) == "table" and options or {}
    local maximumDepth = math.max(0, math.floor(tonumber(options.maxDepth) or 8))
    local maximumValues = math.max(1,
        math.floor(tonumber(options.maxEntries or options.maxValues) or 1024))
    local seen, count = {}, 0

    local function copy(current, depth, path)
        local kind = type(current)
        if kind == "nil" then return nil end
        count = count + 1
        if count > maximumValues then
            error("stable value limit exceeded at " .. path)
        end
        if kind == "string" or kind == "boolean" then return current end
        if kind == "number" then
            if not finite(current) then error("non-finite number at " .. path) end
            return current
        end
        if kind ~= "table" then error("unsupported " .. kind .. " at " .. path) end
        if depth > maximumDepth then error("stable value depth exceeded at " .. path) end
        if seen[current] ~= nil then
            error("cyclic or repeated table at " .. path .. " (first seen at "
                .. seen[current] .. ")")
        end
        seen[current] = path
        local result = {}
        for key, child in pairs(current) do
            local keyType = type(key)
            if keyType ~= "string" and keyType ~= "number" then
                error("unsupported " .. keyType .. " key at " .. path)
            end
            if keyType == "number" and not finite(key) then
                error("non-finite key at " .. path)
            end
            result[key] = copy(child, depth + 1,
                path .. "[" .. tostring(key) .. "]")
        end
        seen[current] = nil
        return result
    end

    local ok, copied = pcall(copy, value, 0, options.path or "$")
    if not ok then return nil, tostring(copied), count end
    return copied, nil, count
end

return StableValue
