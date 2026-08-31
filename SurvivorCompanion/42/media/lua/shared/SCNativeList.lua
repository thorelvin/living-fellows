-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCNamespace")
    pcall(require, "SCCall")
end

local SC = SurvivorCompanion
SC.NativeList = SC.NativeList or {}
local NativeList = SC.NativeList

function NativeList.size(value)
    if value == nil then return 0 end
    local lookupOk, callback = pcall(function() return value.size end)
    if lookupOk and type(callback) == "function" then
        local called, count = SC.Call.method(value, "size")
        if called and tonumber(count) then
            return math.max(0, math.floor(tonumber(count)))
        end
        return 0
    end
    return type(value) == "table" and #value or 0
end

function NativeList.get(value, index)
    index = math.max(0, math.floor(tonumber(index) or 0))
    if value == nil then return nil, false end
    local lookupOk, callback = pcall(function() return value.get end)
    if lookupOk and type(callback) == "function" then
        local called, child = SC.Call.method(value, "get", index)
        if called then return child, true end
        return nil, false
    end
    if type(value) == "table" then return value[index + 1], true end
    return nil, false
end

function NativeList.each(value, callback, maximum)
    if type(callback) ~= "function" then return false, "list callback is required" end
    local count = NativeList.size(value)
    maximum = math.max(0, math.floor(tonumber(maximum) or count))
    count = math.min(count, maximum)
    for index = 0, count - 1 do
        local child, available = NativeList.get(value, index)
        if not available then return false, "list item is unavailable at " .. tostring(index) end
        local ok, result = pcall(callback, child, index)
        if not ok then return false, tostring(result) end
        if result == false then return true, index + 1 end
    end
    return true, count
end

return NativeList
