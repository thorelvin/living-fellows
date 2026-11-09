-- SPDX-License-Identifier: MIT
-- Bounded day-offset reads from the native forecaster. Its raw list starts
-- ten days in the past; getForecast(1), not getForecasts().get(1), is tomorrow.
local SC = SurvivorCompanion
SC.OddballForecast = SC.OddballForecast or {}
local Forecast = SC.OddballForecast

local function invoke(object, method, ...)
    if object == nil then return nil end
    local okay, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    if okay then return value end
    return nil
end

local function number(value,lo,hi)
    local n=tonumber(value)
    if n and n==n and n>=lo and n<=hi then return n end
end
function Forecast.day(offset)
    offset=tonumber(offset)
    if not offset or offset~=math.floor(offset) or offset<0 or offset>6 then return nil end
    if type(getClimateManager) ~= "function" then return nil end
    local okay, climate = pcall(getClimateManager)
    if not okay or climate == nil then return nil end
    local day = invoke(invoke(climate, "getClimateForecaster"), "getForecast", offset)
    if day == nil then return nil end
    -- A stale or overridden forecaster must not silently give another day.
    if invoke(day,"getIndexOffset")~=offset then return nil end
    local function has(method) return invoke(day, method) == true end
    local weather=has("isWeatherStarts") or invoke(day,"getWeatherOverlap")~=nil
    local storm=has("isHasStorm") or has("isHasTropicalStorm") or has("isHasBlizzard")
    local snow=has("isHasBlizzard") or weather and has("isChanceOnSnow")
    local sky
    if has("isHasBlizzard") then
        sky = "a blizzard"
    elseif has("isHasTropicalStorm") or has("isHasStorm") then
        sky = "a thunderstorm"
    elseif has("isHasHeavyRain") then
        sky = "heavy rain"
    elseif weather then
        sky = snow and "snow" or "rain"
    elseif has("isHasFog") then
        sky = "fog"
    else
        local clouds = number(invoke(invoke(day, "getCloudiness"), "getDayMean"),0,1)
        if clouds == nil then return nil end
        sky = clouds >= 0.6 and "clouds" or clouds >= 0.3 and "a few clouds"
            or "clear skies"
    end
    local temperature=invoke(day,"getTemperature")
    local high = number(invoke(temperature,"getDayMax"),-100,100)
    local low=number(invoke(temperature,"getTotalMin"),-100,100)
    local mean=number(invoke(temperature,"getDayMean"),-100,100)
    if high and high >= 30 then
        sky = sky .. ", and hot"
    elseif high and high <= 0 then
        sky = sky .. ", and freezing"
    end
    return {offset=offset,sky=sky,high=high,low=low,temperature=mean,
        storm=storm,snow=snow,fog=has("isHasFog"),frost=low~=nil and low<=0,
        complete=mean~=nil and low~=nil and type(invoke(day,"isHasStorm"))=="boolean"
            and type(invoke(day,"isHasFog"))=="boolean" and type(invoke(day,"isChanceOnSnow"))=="boolean"
            and type(invoke(day,"isWeatherStarts"))=="boolean" and type(invoke(day,"isHasBlizzard"))=="boolean"
            and type(invoke(day,"isHasTropicalStorm"))=="boolean" and type(invoke(day,"isHasHeavyRain"))=="boolean"}
end
-- Existing callers expect words, not the new plain-data snapshot.
function Forecast.tomorrow()
    local day=Forecast.day(1)
    return day and day.sky or nil
end
function Forecast.next(kind)
    if kind~="storm" and kind~="snow" and kind~="fog" and kind~="frost" then return nil,false end
    local complete=true
    for offset=0,6 do
        local day=Forecast.day(offset)
        if not day or not day.complete then complete=false end
        if day and day[kind] then return day,complete end
    end
    return nil,complete
end

return Forecast
