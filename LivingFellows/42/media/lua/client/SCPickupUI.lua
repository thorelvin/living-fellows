-- SPDX-License-Identifier: MIT
if type(require)=="function" then
    require "ISUI/ISPanel"
    require "ISUI/ISButton"
    require "ISUI/ISComboBox"
end
LivingFellows=LivingFellows or {}
local SC=LivingFellows
local UI={}
SC.PickupUI=UI
local window
local reasons={pickup_no_radio_contact="No reply. Check both radios, their channel and their range.",
    pickup_loading_camp="Contacting camp...",pickup_restoring_driver="Waiting for the driver to return...",
    pickup_no_available_driver_or_car="No available camp driver and parked car. Check camp duty, keys and parking.",
    too_few_seats="The car needs a seat for you and each nearby companion coming along.",
    driver_needs_key="The driver needs this car's key, or a car that can already be started.",
    driver_needs_key_from_player="Give the camp driver the car key before calling.",
    fuel_insufficient="There is not enough fuel for this journey and the return to camp.",
    pickup_waiting_for_companions="Waiting for your companions to board. You can choose to leave without them.",
    pickup_waiting_for_passengers_to_exit="Get out when you are ready. The driver returns after everyone has left the car.",
    pickup_primary_view_pending="Come closer to the car so the driver can wait for you.",
    pickup_primary_car_pending="Come closer to the parked car.",pickup_board_first="Get into a passenger seat first.",
    pickup_bridge_unavailable="Pickup needs the matching Living Fellows bridge.",
    pickup_other_trip_active="Finish the current trip before calling for a pickup.",
    pickup_camp_changed="The camp or its parking has changed. Restore it before retrying.",
    pickup_driver_died="The driver has died. The pickup is held.",
    pickup_driver_changed="Someone else has taken the wheel. The pickup is held.",
    pickup_new_player_order="The driver has a new order. The pickup is held.",
    pickup_survival_priority="The driver stopped to deal with an urgent need or danger. Retry when ready.",
    pickup_wait_timed_out="The driver could not complete this step. Retry when the way is clear.",
    pickup_car_save_failed="The parked car could not be saved. Retry to keep the return safe.",
    pickup_arrival_retry="Camp handover paused. Retry to finish saving the return.",
    pickup_restore_retry="The journey could not finish loading. Retry to load the same agreed trip.",
    pickup_route_blocked="The car could not make progress. Clear the way, then Retry.",
    pickup_no_return_route="No return route to camp is available from that pickup point.",
    pickup_request_changed="The pickup changed during the call. Review it before trying again.",
    pickup_no_safe_road="No clear roadside pickup point nearby. Move towards an open street.",
    pickup_ground_floor_required="Go outside at ground level to arrange the pickup.",
    pickup_caller_on_foot_required="Get out of your car before calling for a pickup.",
    pickup_caller_unavailable="The caller is unavailable. The journey is held.",
    pickup_finding_road="Finding a pickup point. Waiting for the driver's reply.",
    pickup_passenger_left="The passenger ride stopped. Get back in before retrying, or cancel to send the car home.",
    pickup_loading_car="Waiting for the saved car to load...",
    pickup_parking_approach="Pulling into the camp parking space.",
    parking_approach_timeout="The car could not reach its camp parking space. Clear the approach, then Retry."}
local phases={acquire="The driver is preparing to leave camp.",board_driver="The driver is getting into the car.",
    outbound="The driver is on the way to the agreed pickup point.",pickup_handoff="The driver has arrived. Come over to the car.",
    waiting_board="Your ride is waiting. Get into a passenger seat, then choose Home or a place on the map.",
    ride_start="Preparing to leave.",ride="On the way to your destination.",drop_wait="The car is stopped. Get out when ready.",
    acquire_return="Preparing to return the empty car to camp.",returning="Returning the car to camp.",
    parked="Parking at camp.",exit_driver="The driver is getting out at camp.",camp_arrival="The driver is returning to camp duty.",
    finish="Finishing the return to camp.",held="The journey is held. Check the reason below, then Retry."}
function UI.reason(reason) return reasons[reason] or "The pickup is not ready. Check the car, driver and radio contact." end
function UI.note(player,okay,reason)
    if window then window.notice=okay and "Received." or UI.reason(reason) end
    if player and type(player.setHaloNote)=="function" then
        player:setHaloNote(okay and "Pickup order received." or UI.reason(reason))
    end
end
local function action(panel,name,...)
    local current=SC.PickupService.current() or SC.PickupService.previewCurrent()
    if panel.snapshot and panel.snapshot~=current then panel.notice="The pickup has changed. Open the sheet again." return false end
    local okay,reason=SC.PickupService[name](...)
    panel.notice=okay and "Received." or UI.reason(reason)
    return okay
end
local function close(panel)
    if SC.PickupService.previewCurrent() then SC.PickupService.closePreview() end
    panel:removeFromUIManager()
    window=nil
end
local function wrapped(panel,text,y,r,g,b)
    local manager=getTextManager()
    local line,height="",manager:getFontHeight(UIFont.Small)
    for word in tostring(text or ""):gmatch("%S+") do
        local nextLine=line=="" and word or line.." "..word
        if line~="" and manager:MeasureStringX(UIFont.Small,nextLine)>panel.width-36 then
            panel:drawText(line,18,y,r or 1,g or 1,b or 1,1,UIFont.Small)
            y,line=y+height,word
        else line=nextLine end
    end
    if line~="" then panel:drawText(line,18,y,r or 1,g or 1,b or 1,1,UIFont.Small) y=y+height end
    return y
end
local function build()
    local Panel=ISPanel:derive("LFCampPickupPanel")
    function Panel:createChildren()
        ISPanel.createChildren(self)
        self.driver=ISComboBox:new(18,84,self.width-36,24,self,function(panel)
            if panel.changing then return end
            SC.PickupService.select(panel.driverIds[panel.driver.selected],panel.carIds[panel.car.selected])
        end)
        self.car=ISComboBox:new(18,136,self.width-36,24,self,function(panel)
            if panel.changing then return end
            SC.PickupService.select(panel.driverIds[panel.driver.selected],panel.carIds[panel.car.selected])
        end)
        self:addChild(self.driver) self:addChild(self.car)
        self.buttons={}
        local function button(label,x,y,width,callback)
            local b=ISButton:new(x,y,width,26,label,self,callback)
            b:initialise() b:instantiate() self:addChild(b)
            self.buttons[#self.buttons+1]=b
            return b
        end
        self.request=button("Come pick us up",18,294,166,function(panel) action(panel,"request",panel.player,panel.source) end)
        self.home=button("Take us Home",18,294,166,function(panel) action(panel,"departHome",false) end)
        self.leave=button("Home without waiting",194,294,220,function(panel) action(panel,"departHome",true) end)
        self.updatePoint=button("Update pickup",18,328,166,function(panel) action(panel,"updatePickup",panel.source) end)
        self.retry=button("Retry journey",18,328,166,function(panel) action(panel,"retry",panel.source) end)
        self.cancelTrip=button("Cancel and return",194,328,220,function(panel) action(panel,"cancel",panel.source) end)
        self.status=button("Ask for status",18,362,166,function(panel) action(panel,"radioStatus",panel.source) end)
        self.endHere=button("End pickup here",194,362,220,function(panel) action(panel,"endHere") end)
        button("Close",self.width-108,362,90,close)
    end
    function Panel:update()
        ISPanel.update(self)
        local ctx=SC.PickupService.current() or SC.PickupService.previewCurrent()
        local preview=SC.PickupService.previewCurrent()
        self.snapshot=ctx
        if not ctx then self.lastOutcome=SC.PickupService.describe().outcome end
        self.driver:setVisible(preview~=nil) self.car:setVisible(preview~=nil)
        self.request:setVisible(preview~=nil) self.request:setEnable(preview and preview.ready==true)
        local partyCount=preview and #(preview.party or {}) or 0
        local requestTitle=partyCount>0 and "Come pick us up" or "Come pick me up"
        if self.request.title~=requestTitle then self.request:setTitle(requestTitle) end
        local waiting=ctx and ctx.phase=="waiting_board"
        local missing=false
        if waiting then
            local car=SC.Vehicle.loadedBySqlId(ctx.carSqlId)
            for id,seat in pairs(ctx.seats) do
                local record=SC.Registry.byId(id)
                if id~=ctx.driverId and SC.PickupDispatch.stillComing(id,car)
                    and (not record or (SC.GameplayUtil.call(car,"getCharacter",seat))~=record.actor) then missing=true end
            end
        end
        self.home:setVisible(waiting==true) self.leave:setVisible(waiting==true and missing)
        self.updatePoint:setVisible(ctx~=nil and not preview and (waiting or ctx.phase=="outbound" or ctx.phase=="pickup_handoff"))
        self.updatePoint:setEnable(ctx~=nil and not ctx.updateRequested)
        self.retry:setVisible(ctx~=nil and ctx.phase=="held")
        self.cancelTrip:setVisible(ctx~=nil and not preview)
        self.status:setVisible(ctx~=nil and not preview)
        self.endHere:setVisible(ctx~=nil and ctx.phase=="held")
        if preview and preview.drivers~=self.rows then
            self.rows=preview.drivers
            self.changing=true
            self.driver:clear() self.car:clear()
            self.driver:addOption("Automatic") self.car:addOption("Automatic")
            self.driverIds,self.carIds={},{}
            for _,row in ipairs(preview.drivers or {}) do
                self.driver:addOption(row.name) self.driverIds[#self.driver.options]=row.id
                if row.id==preview.selectedDriver then self.driver.selected=#self.driver.options end
            end
            for _,row in ipairs(preview.cars or {}) do
                self.car:addOption(row.name.." / "..tostring(row.seats).." seats") self.carIds[#self.car.options]=row.sqlId
                if row.sqlId==preview.selectedCar then self.car.selected=#self.car.options end
            end
            self.changing=nil
        end
    end
    function Panel:render()
        ISPanel.render(self)
        self:drawText("Camp pickup",18,14,1,.92,.75,1,UIFont.Large)
        local ctx=self.snapshot
        if not ctx then
            local last=self.lastOutcome
            local text=last and (last.result=="returned" and "The car is back at camp."
                or last.result=="driver_lost" and "The driver has died. The car remains where it stopped."
                or "The pickup ended here.") or "No pickup is active."
            self:drawText(text,18,54,1,1,1,1,UIFont.Small) return
        end
        if ctx.phase=="preview" then
            self:drawText("Driver",18,62,1,1,1,1,UIFont.Small)
            self:drawText("Car",18,114,1,1,1,1,UIFont.Small)
            local record=ctx.driverId and SC.Registry.byId(ctx.driverId)
            local name=record and SC.GameplayUtil.nameOf(record.actor)
            self:drawText(ctx.ready and ("Selected: "..tostring(name or "camp driver")) or "Checking camp and a roadside stop...",18,172,1,1,1,1,UIFont.Small)
            if ctx.ready and ctx.plan then
                local carName=SC.ExpeditionCar.displayName(ctx.plan.vehicle)
                self:drawText("Car: "..carName..string.format(" / Fuel: %.1f L",ctx.plan.fuel or 0),18,192,1,1,1,1,UIFont.Small)
            end
            local count=#(ctx.party or {})
            local party=count==0 and "Coming along: just you." or ("Coming along: you and "..count..(count==1 and " companion." or " companions."))
            self:drawText(party,18,212,1,1,1,1,UIFont.Small)
        else
            local y=wrapped(self,phases[ctx.phase] or "Preparing the pickup.",62)
            y=wrapped(self,"Right-click the map while aboard to choose another destination.",y+8,.85,.85,.85)
            wrapped(self,"The driver brings the car back to camp after everyone gets out.",y+8,.85,.85,.85)
        end
        if ctx.pickup then self:drawText(string.format("Agreed pickup: %.0f, %.0f",ctx.pickup.x,ctx.pickup.y),18,234,.9,.9,.9,1,UIFont.Small) end
        wrapped(self,self.notice or (ctx.reason and UI.reason(ctx.reason)) or "",250,1,.85,.6)
    end
    return Panel
end
function UI.open(player,source)
    if window then
        if source~=nil then window.source=source end
        window:bringToTop() return true
    end
    if not SC.PickupService.current() then
        local okay,reason=SC.PickupService.beginPreview(player,source)
        if not okay then UI.note(player,false,reason) return false,reason end
    end
    local Panel=build()
    local width=math.min(620,getCore():getScreenWidth()-32)
    window=Panel:new((getCore():getScreenWidth()-width)/2,70,width,412)
    window.player,window.source=player,source
    window.moveWithMouse=true window.backgroundColor={r=.08,g=.09,b=.08,a=.96}
    window:initialise() window:instantiate() window:addToUIManager()
    return true
end
function UI.fillInventory(context,player,item)
    if not SC.PickupService.available() or not SC.PickupRadio.caller(player,item) then return false end
    context:addOption("Camp pickup...",nil,function() UI.open(player,item) end)
    return true
end
function UI.fillLocal(context,player,car)
    local ctx=SC.PickupService.current()
    if ctx and (car==SC.Vehicle.loadedBySqlId(ctx.carSqlId)
        or SC.PickupRadio.localContact(player,ctx.actor)) then
        context:addOption("Camp pickup...",nil,function() UI.open(player,nil) end)
        return true
    end
end
function UI.fillMap(context,player,target)
    local ctx=SC.PickupService.current()
    if not ctx or ctx.phase~="waiting_board" or not SC.PickupService.isBookedPassenger(player,SC.Vehicle.loadedBySqlId(ctx.carSqlId)) then return false end
    local function depart(leaveMissing)
        local route,reason=SC.PickupDispatch.route(ctx,SC.Vehicle.loadedBySqlId(ctx.carSqlId),target,true)
        if not route then UI.note(player,false,reason) return end
        local stop=route.exit
        local okay,reason=SC.PickupService.depart(stop,leaveMissing)
        UI.note(player,okay,reason)
    end
    context:addOption("Ask pickup driver to take us here",nil,function() depart(false) end)
    local car=SC.Vehicle.loadedBySqlId(ctx.carSqlId)
    for id,seat in pairs(ctx.seats) do
        local record=SC.Registry.byId(id)
        if id~=ctx.driverId and SC.PickupDispatch.stillComing(id,car)
            and (not record or (SC.GameplayUtil.call(car,"getCharacter",seat))~=record.actor) then
            context:addOption("Take us here without waiting for companions",nil,function() depart(true) end)
            break
        end
    end
    return true
end
function UI.reset()
    if window then window:removeFromUIManager() window=nil end
    return true
end
return UI
