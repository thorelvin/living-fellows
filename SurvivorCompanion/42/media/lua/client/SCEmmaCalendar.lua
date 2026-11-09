-- SPDX-License-Identifier: MIT
-- Native calendar facts, read only on a foreground request. No clock service.
require "SCOddballForecast"
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local C={} SC.EmmaCalendar=C
local function call(object,key,...)
    if not object then return nil end
    local okay,value=pcall(function(...) return object[key](object,...) end,...)
    if okay then return value end
end
local function number(value,lo,hi)
    local n=tonumber(value)
    if n and n==n and n>=lo and n<=hi then return n end
end
local function global(fn)
    if type(fn)~="function" then return nil end
    local okay,value=pcall(fn)
    if okay then return value end
end
local function option(options,key,fallback)
    return number(call(call(options,"getOptionByName",key),"getValue"),-1,2147483647)
        or number(fallback,-1,2147483647)
end
function C.clock()
    local time=global(getGameTime)
    if not time then return nil end
    return {year=number(call(time,"getYear"),1,9999),month=number(call(time,"getMonth"),0,11),
        day=number(call(time,"getDay"),0,30),hour=number(call(time,"getTimeOfDay"),0,24),
        nights=number(call(time,"getNightsSurvived"),0,10000000),
        age=number(call(global(getWorld),"getWorldAgeDays"),0,10000000)}
end
function C.daylight()
    local season=call(global(getClimateManager),"getSeason")
    local dawn,dusk=number(call(season,"getDawn"),0,24),number(call(season,"getDusk"),0,24)
    local clock=C.clock()
    if not clock or not clock.hour or not dawn or not dusk then return nil end
    return {dawn=dawn,dusk=dusk,hour=clock.hour}
end
local function shutoff(modifier,age)
    if modifier==nil or age==nil then return nil end
    return {at=modifier,left=(modifier-age)*24,never=modifier>=100000}
end
function C.read(kind,query)
    local clock=C.clock()
    if not clock then return nil end
    local options=global(getSandboxOptions)
    local time=global(getGameTime)
    local result={clock=clock}
    if kind=="forecast" then
        query=query or {}
        if query.weather then result.forecast,result.complete=SC.OddballForecast.next(query.weather)
        else result.forecast=SC.OddballForecast.day(query.day or 1) end
        return result
    end
    if kind=="water_off" or kind=="calendar" then
        result.water=shutoff(number(call(options,"getWaterShutModifier"),-1,2147483647),clock.age)
    end
    if kind=="power_off" or kind=="calendar" then
        local modifier=number(call(options,"getElecShutModifier"),-1,2147483647)
        local grid=SC.GridControl and SC.GridControl.snapshot and SC.GridControl.snapshot(nil)
        if type(grid)=="table" and grid.visible and number(grid.originalShut,-1,2147483647) then
            modifier=grid.originalShut
        end
        result.power=shutoff(modifier,clock.age)
        if result.power and grid then
            result.power.restored=grid.on==true and (tonumber(grid.remainingHours) or 0)>0
                and result.power.left<=0
            result.power.remainingHours=result.power.restored and grid.remainingHours or nil
        end
    end
    if kind=="helicopter" or kind=="calendar" then
        local setting=option(options,"Helicopter",SandboxVars and SandboxVars.Helicopter)
        local target=number(call(time,"getHelicopterDay1"),0,10000000)
        local start=number(call(time,"getHelicopterStartHour"),0,24)
        local finish=number(call(time,"getHelicopterEndHour"),0,24)
        local active
        local world=global(getWorld)
        local okay,helicopter=pcall(function() return world and world.helicopter end)
        if okay then active=call(helicopter,"isActive") end
        if active==true then result.helicopter={state="active",offset=target and clock.nights and target-clock.nights or 0,
            start=start,finish=finish,left=0}
        elseif setting==1 then result.helicopter={state="none"}
        elseif setting and target and start and finish and finish>=start and clock.nights and clock.hour then
            local days=target-clock.nights
            local state=days<0 and "after" or days>1 and "before" or days==1 and "soon"
                or clock.hour>=finish and "after" or clock.hour>start and "window" or "soon"
            if active==true then state="active" end
            result.helicopter={state=state,offset=days,start=start,finish=finish,repeatable=setting>=3,
                left=days*24+start-clock.hour}
        end
    end
    return result
end
local months={"January","February","March","April","May","June","July","August","September","October","November","December"}
local function monthDays(year,month)
    if month==2 then return year%4==0 and (year%100~=0 or year%400==0) and 29 or 28 end
    return (month==4 or month==6 or month==9 or month==11) and 30 or 31
end
-- Use only the in-world date; operating-system time and timezone never enter it.
function C.date(clock,offset)
    if not clock or not clock.year or not clock.month or clock.day==nil then return nil end
    offset=number(offset,-36600,36600)
    if not offset then return nil end
    local year,month,day=math.floor(clock.year),math.floor(clock.month)+1,math.floor(clock.day)+1+math.floor(offset)
    while day>monthDays(year,month) do
        day=day-monthDays(year,month);month=month+1
        if month>12 then month=1;year=year+1 end
    end
    while day<1 do
        month=month-1;if month<1 then month=12;year=year-1 end
        day=day+monthDays(year,month)
    end
    if year<1 or year>9999 then return nil end
    return months[month].." "..day..", "..year
end
function C.time(hours)
    hours=number(hours,0,10000000)
    if not hours then return nil end
    local minutes=math.floor(hours*60+.00001)%1440
    return string.format("%02d:%02d",math.floor(minutes/60),minutes%60)
end
return C
