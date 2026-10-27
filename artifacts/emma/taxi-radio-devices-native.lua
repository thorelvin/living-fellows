-- SPDX-License-Identifier: MIT
-- Native inventory classes/device data and the production menu builder.
-- Private cloned world only; never dispatches a cab or invokes a valid booking.
local finished=false
local function log(value)
    print("TAXI_RADIO_DEVICES|"..value)
    local writer=getFileWriter("SurvivorCompanionHarness/taxi-radio-devices.log",true,true)
    if writer then writer:write(value.."\n") writer:close() end
end
local function menu()
    local result={options={}}
    function result:addOption(label,target,callback,...)
        local option={label=label,target=target,callback=callback,args={...}}
        self.options[#self.options+1]=option return option
    end
    result.addOptionOnTop=result.addOption
    function result:addSubMenu(option,child) option.subMenu=child end
    return result
end
local function hasTaxi(root)
    for _,option in ipairs(root.options) do
        if option.label==getText("UI_SC_Taxi_Menu") then return true end
    end
    return false
end
local function inspect(player,items)
    local previous=ISContextMenu.getNew
    ISContextMenu.getNew=function() return menu() end
    local root=menu()
    local okay,reason=pcall(SurvivorCompanion.UIContext.fillRadioContextMenu,0,root,items)
    ISContextMenu.getNew=previous
    assert(okay,tostring(reason))
    return root
end
Events.OnTick.Add(function()
    local player=getSpecificPlayer(0) local SC=SurvivorCompanion
    if finished or not player or not player:getSquare() or not SC or not SC.UIContext then return end
    finished=true
    local inventory=player:getInventory() local created={}
    local function item(id)
        local value=inventory:AddItem(id) assert(value,"native item unavailable: "..id)
        created[#created+1]=value return value
    end
    local okay,reason=pcall(function()
        local tv
        for _,id in ipairs({"Base.TvAntique","Base.TvBlack","Base.TvWideScreen"}) do
            tv=item(id)
            local data=tv:getDeviceData()
            assert(instanceof(tv,"Radio") and data:getIsTelevision(),"native TV class/flag differs")
            assert(not data:getIsPortable() and not data:getIsTwoWay() and data:getTransmitRange()==0,"stock TV flags differ")
            local ready,why=SC.TaxiBooking.checkRadio(player,tv)
            assert(not ready and why=="not_a_radio","native TV passed booking validation")
            assert(not hasTaxi(inspect(player,{tv})),"native TV still has taxi menu")
            log("PASS "..id.." native Radio class; TV rejected; no taxi menu")
        end
        local receiver=item("Base.RadioRed")
        assert(not receiver:getDeviceData():getIsTwoWay(),"receive-only fixture changed")
        assert(not hasTaxi(inspect(player,{receiver})),"receive-only radio has taxi menu")
        local radio=item("Base.WalkieTalkie2") local data=radio:getDeviceData()
        data:setHasBattery(true) data:setPower(1) data:setIsTurnedOn(true)
        assert(SC.TaxiBooking.checkRadio(player,radio),"working native handset rejected")
        assert(hasTaxi(inspect(player,{radio})),"working native handset lost taxi menu")
        assert(hasTaxi(inspect(player,{{items={tv,receiver,radio}}})),"mixed native item stack lost valid handset")
        data:setIsTurnedOn(false)
        assert(not hasTaxi(inspect(player,{radio})),"off native handset has taxi menu")
        data:setIsTurnedOn(true) data:setIsTelevision(true)
        assert(not SC.TaxiBooking.request(player,radio),"delayed callback accepted a TV-marked device")
        assert(not hasTaxi(inspect(player,{radio})),"TV flag lost priority over working transmitter fields")
        log("PASS native receive-only/off rejection, valid walkie, mixed selection and stale TV callback")
    end)
    for _,value in ipairs(created) do inventory:Remove(value) end
    if not okay then log("FAIL "..tostring(reason))
    else log("PASS native taxi radio devices acceptance complete") end
end)
