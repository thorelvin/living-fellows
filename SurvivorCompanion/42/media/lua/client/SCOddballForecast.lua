-- SPDX-License-Identifier: MIT
-- Tomorrow's weather in a few plain words, read from the game's own
-- forecaster. DayForecast.getName() is only the date ("Day: 1993 - 7 - 5");
-- live on 42.21, Hatcher's sitrep read that out as the weather. The day's
-- own flags and cloud cover say what the sky will do.
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

-- Words that read after "Tomorrow looks like" and after "Tomorrow's sky?".
function Forecast.tomorrow()
    if type(getClimateManager) ~= "function" then return nil end
    local okay, climate = pcall(getClimateManager)
    if not okay or climate == nil then return nil end
    local forecasts = invoke(invoke(climate, "getClimateForecaster"), "getForecasts")
    if (tonumber(invoke(forecasts, "size")) or 0) < 2 then return nil end
    local day = invoke(forecasts, "get", 1)
    if day == nil then return nil end
    local function has(method) return invoke(day, method) == true end
    local sky
    if has("isHasBlizzard") then
        sky = "a blizzard"
    elseif has("isHasTropicalStorm") or has("isHasStorm") then
        sky = "a thunderstorm"
    elseif has("isHasHeavyRain") then
        sky = "heavy rain"
    elseif has("isWeatherStarts") then
        sky = has("isChanceOnSnow") and "snow" or "rain"
    elseif has("isHasFog") then
        sky = "fog"
    else
        local clouds = tonumber(invoke(invoke(day, "getCloudiness"), "getDayMean"))
        if clouds == nil then return nil end
        sky = clouds >= 0.6 and "clouds" or clouds >= 0.3 and "a few clouds"
            or "clear skies"
    end
    local high = tonumber(invoke(invoke(day, "getTemperature"), "getDayMax"))
    if high and high >= 30 then
        sky = sky .. ", and hot"
    elseif high and high <= 0 then
        sky = sky .. ", and freezing"
    end
    return sky
end

return Forecast
