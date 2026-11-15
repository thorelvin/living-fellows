-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.LifeEvents = SC.LifeEvents or {}
local LifeEvents = SC.LifeEvents
local queue = {}
local nextSerial = 1

local function clean(value, fallback, maximum)
    local result = type(value) == "string" and value or fallback or ""
    result = string.gsub(result, "[\r\n\t]", " ")
    if maximum and #result > maximum then result = string.sub(result, 1, maximum) end
    return result
end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback or 0
    end
    return value
end

local function gameTimeMs()
    if type(getGameTime) == "function" then
        local ok, gameTime = pcall(getGameTime)
        if ok and gameTime ~= nil then
            local ageOk, hours = pcall(gameTime.getWorldAgeHours, gameTime)
            if ageOk and finite(hours, -1) >= 0 then
                return math.floor(finite(hours, 0) * 3600000)
            end
        end
    end
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function" then
        return SC.GameplayUtil.nowMs()
    end
    return math.floor(os.clock() * 1000)
end

local function participants(source)
    local result, seen = {}, {}
    if type(source) == "table" then
        for _, value in ipairs(source) do
            local id = type(value) == "string" and clean(value, "", 80) or nil
            if id and id ~= "" and not seen[id] then
                seen[id] = true
                result[#result + 1] = id
                if #result >= 16 then break end
            end
        end
    end
    return result
end

local function stableFields(source)
    local result, count = {}, 0
    if type(source) ~= "table" then return result end
    for key, value in pairs(source) do
        if type(key) == "string" and key ~= "participants" and key~="witnesses" then
            local kind = type(value)
            if kind == "string" then result[key] = clean(value, "", 160)
            elseif kind == "number" then result[key] = finite(value, 0)
            elseif kind == "boolean" then result[key] = value end
            count = count + 1
            if count >= 32 then break end
        end
    end
    return result
end

function LifeEvents.now()
    return gameTimeMs()
end

function LifeEvents.emit(kind, fields)
    if type(kind) ~= "string" or kind == "" then return nil, "invalid_event_kind" end
    local row = stableFields(fields)
    row.kind = clean(kind, "event", 48)
    row.at = math.max(0, math.floor(finite(type(fields) == "table" and fields.at, gameTimeMs())))
    local wall=SC.GameplayUtil and SC.GameplayUtil.nowMs and SC.GameplayUtil.nowMs() or 0
    row.id = "life-"..tostring(row.at).."-"..tostring(math.floor(finite(wall,0))).."-"..tostring(nextSerial)
    nextSerial = nextSerial + 1
    row.participants = participants(type(fields) == "table" and fields.participants)
    row.witnesses = participants(type(fields) == "table" and fields.witnesses)
    if row.day==nil then row.day=math.floor(row.at/86400000) end
    if row.hour==nil then row.hour=(row.at/3600000)%24 end
    if SC.SharedHistory then row=SC.SharedHistory.cleanRow(row) end
    queue[#queue + 1] = row
    while #queue > 128 do table.remove(queue, 1) end
    -- Private diaries observe without draining; SCCommunity owns the queue.
    if SC.Diary and type(SC.Diary.observeLifeEvent) == "function" then
        pcall(SC.Diary.observeLifeEvent, row)
    end
    return row
end

-- Producers call this while they already own the observed actor/facts. Looking
-- up at most 16 named registry IDs does not discover actors or infer witnesses.
function LifeEvents.observed(kind,actor,fields)
    local values={} for key,value in pairs(fields or {}) do values[key]=value end
    local u=SC.GameplayUtil
    if actor and u then
        values.sourceId=values.sourceId or u.idOf(actor)
        values.sourceName=values.sourceName or u.nameOf(actor)
        if values.place==nil and SC.Tales and SC.Tales.placeOf then values.place=SC.Tales.placeOf(actor) end
    end
    if u then
        local target=values.targetId and u.resolveActor and u.resolveActor(values.targetId)
        if target and not values.targetName then values.targetName=u.nameOf(target) end
        for _,key in ipairs({"participants","witnesses"}) do
            local names={}
            for n,id in ipairs(type(values[key])=="table" and values[key] or {}) do
                if n>16 then break end
                local known=u.resolveActor and u.resolveActor(id)
                if known then names[#names+1]=u.nameOf(known) end
            end
            local nameKey=key=="participants" and "participantNames" or "witnessNames"
            if #names>0 and values[nameKey]==nil then values[nameKey]=table.concat(names,", ") end
        end
    end
    return LifeEvents.emit(kind,values)
end

function LifeEvents.drain(limit)
    limit = math.max(1, math.min(64, math.floor(finite(limit, 32))))
    local result = {}
    while #queue > 0 and #result < limit do
        result[#result + 1] = table.remove(queue, 1)
    end
    return result
end

function LifeEvents.peek()
    local result = {}
    for index, row in ipairs(queue) do result[index] = row end
    return result
end

function LifeEvents.reset()
    queue, nextSerial = {}, 1
end

return LifeEvents
