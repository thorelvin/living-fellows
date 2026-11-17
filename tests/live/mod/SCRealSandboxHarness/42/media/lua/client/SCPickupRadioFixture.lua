-- SPDX-License-Identifier: MIT
-- Clone-only real computers and hardware; provision before measuring packets.
local Q={}
function Q.prepare(H,t,check)
    local SC,player=SurvivorCompanion,H.player
    local car=t.vehicle
    local x,y=math.floor(car:getX()),math.floor(car:getY())
    local created,reason=SC.BaseLife.create({x=x,y=y,z=0},"Pickup radio fixture")
    if not check("pickup_radio_camp_setup",created,tostring(reason)) then return false end
    SC.BaseLife.beginZone("area",{x=x-16,y=y-16,z=0})
    local marked,reason=SC.BaseLife.finishZone({x=x+16,y=y+16,z=0},"Radio test camp")
    if not check("pickup_radio_area_setup",marked,tostring(reason)) then return false end
    -- Electrical work and real consumable parts belong to setup only.
    player:setPerkLevelDebug(Perks.Electricity,math.max(4,player:getPerkLevel(Perks.Electricity)))
    local inventory=player:getInventory()
    inventory:AddItem("Base.Screwdriver")
    for _=1,6 do inventory:AddItem("Base.ElectricWire") end
    for _=1,14 do inventory:AddItem("Base.ElectronicsScrap") end
    local pcs,parts={},{}
    for index,offset in ipairs({{6,8},{-6,-8}}) do
        local square=SC.GameplayUtil.gridSquare(x+offset[1],y+offset[2],0)
        if not check("pickup_radio_pc_square_"..index,square~=nil,"loaded native floor") then return false end
        local pc=IsoObject.new(square,"appliances_com_01_72","Computer")
        square:AddTileObject(pc)
        local os=SC.Terminal.computerState(player,pc)
        if not check("pickup_radio_pc_identity_"..index,os~=nil,"actual computer object") then return false end
        os.locked=false
        local radio=inventory:AddItem("Base.WalkieTalkie2")
        radio:getDeviceData():setChannel(t.radioKit.player:getDeviceData():getChannel())
        local battery=inventory:AddItem("Base.CarBattery1")
        SC.ControlUtil.setCharge(battery,.9)
        pcs[index]=pc
        parts[index]={radio=radio,battery=battery}
    end
    player:teleportTo(pcs[1]:getX()+.5,pcs[1]:getY()+.5,0)
    t.radioPCs,t.radioPCParts,t.radioPCBuild=pcs,parts,1
    return true
end
function Q.install(H,t,check)
    local SC,player=SurvivorCompanion,H.player
    local index=t.radioPCBuild
    if not index then return true end
    local pc=t.radioPCs[math.min(index,2)]
    if index>2 then pc=t.radioPCs[1] end
    if not SC.ControlUtil.near(player,pc,3) then return nil end
    if index>2 then t.radioPCBuild=nil return true end
    local okay,reason=SC.TerminalHardware.install(player,pc,"radio",t.radioPCParts[index].radio)
    if not check("pickup_radio_pc_mount_"..index,okay,tostring(reason)) then return false end
    local okay,reason=SC.TerminalHardware.install(player,pc,"ups",t.radioPCParts[index].battery)
    if not check("pickup_radio_pc_supply_"..index,okay,tostring(reason)) then return false end
    t.radioPCBuild=index+1
    local nextPC=t.radioPCs[index==1 and 2 or 1]
    player:teleportTo(nextPC:getX()+.5,nextPC:getY()+.5,0)
    return nil
end
function Q.measure(H,t,check)
    local SC=SurvivorCompanion
    local caller=SC.PickupRadio.caller(H.player,t.radioKit.player)
    local driver=SC.PickupRadio.driver(t.actor)
    local station,why=SC.RadioEndpoints.station(H.player,t.radioPCs[1])
    if not check("pickup_radio_caller_station",station~=nil,tostring(why)) then return false end
    local camp,why=SC.RadioEndpoints.campStation(H.player,t.radioPCs[2],SC.BaseLife.active().id)
    if not check("pickup_radio_camp_station",camp~=nil,tostring(why)) then return false end
    for i,source in ipairs({caller,station}) do
        for j,target in ipairs({driver,camp}) do
            local okay,reason=SC.PickupRadio.exchange(source,target,t.pickup.requestId,"status")
            if not check("pickup_radio_native_pair_"..i.."_"..j,okay,tostring(reason)) then return false end
        end
    end
    t.radioNoHandset=t.actor:getSecondaryHandItem()
    t.actor:setSecondaryHandItem(nil)
    t.radioRelayStation,t.radioRelayCamp=station,camp
    return true
end
function Q.relay(H,t,check)
    local SC=SurvivorCompanion
    if SC.PickupRadio.driver(t.actor)~=nil then return nil end
    local ctx={requestId=t.pickup.requestId,camp=SC.HomeTrip.captureCamp(SC.BaseLife.active()),
        player=H.player,stations={t.radioRelayCamp}}
    local okay,reason=SC.PickupRadio.deliver(ctx,t.actor,t.radioRelayStation,"request",false)
    t.actor:setSecondaryHandItem(t.radioNoHandset)
    t.radioNoHandset=nil
    return check("pickup_radio_native_local_relay",okay,"camp computer to resident without a walkie; "..tostring(reason))
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCPickupRadioFixture=Q
return Q
