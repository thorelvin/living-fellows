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
    local resolved, callback, isNative = SC.Call.resolve(value, "size")
    if resolved then
        SC.Call.traceResolved("size", isNative)
        local called, count = pcall(callback, value)
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
    local resolved, callback, isNative = SC.Call.resolve(value, "get")
    if resolved then
        SC.Call.traceResolved("get", isNative)
        local called, child = pcall(callback, value, index)
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
    local resolved, getMethod, isNative
    if count > 0 then
        resolved, getMethod, isNative = SC.Call.resolve(value, "get")
    end
    for index = 0, count - 1 do
        local child, available
        if resolved then
            SC.Call.traceResolved("get", isNative)
            available, child = pcall(getMethod, value, index)
        elseif type(value) == "table" then
            child, available = value[index + 1], true
        end
        if not available then return false, "list item is unavailable at " .. tostring(index) end
        local ok, result = pcall(callback, child, index)
        if not ok then return false, tostring(result) end
        if result == false then return true, index + 1 end
    end
    return true, count
end

return NativeList
