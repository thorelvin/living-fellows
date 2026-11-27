-- SPDX-License-Identifier: MIT
local F,SC=PICKUP,LivingFellows
local S,check=SC.PickupService,PICKUP.check
local followerState=SC.Commands.peek(F.follower)
F.follower.z=1
check(#SC.PickupDispatch.party(F.player)==1,"nearby party eligibility uses horizontal distance across floors")
F.follower.z=0 F.follower.x=186
check(#SC.PickupDispatch.party(F.player)==0,"companions beyond 35 metres are not summoned")
F.follower.x=151 followerState.rideWithPlayer=false
check(#SC.PickupDispatch.party(F.player)==0,"ride opt-out is respected")
followerState.rideWithPlayer=true followerState.followCarSqlId=88
check(#SC.PickupDispatch.party(F.player)==0,"separate car assignment is respected")
followerState.followCarSqlId=nil followerState.order="stay"
check(not SC.PickupDispatch.stillComing("sc-follower",F.car),"a changed companion order releases its boarding wait")
followerState.order="follow"
F.detached="sc-driver"
check(S.beginPreview(F.player,{radio=true}),"cold preview opens before driver restoration") F.tick()
check(not S.previewCurrent().ready,"pending camp driver is not replaced by a fabricated actor")
F.detached=nil F.time=F.time+2001 F.tick()
check(S.previewCurrent().ready,"cold preview rescans after the real driver finishes restoring")
S.closePreview()
local function ready()
    local okay,reason=S.beginPreview(F.player,{radio=true}) check(okay,"preview opens: "..tostring(reason))
    F.tick() check(S.previewCurrent().ready,"real pair and stop ready")
end
ready()
F.deliver=false
local okay,reason=S.request(F.player,{radio=true})
check(not okay and reason=="pickup_no_radio_contact" and S.current()==nil and F.claim==nil,"undelivered dispatch has no authority")
F.deliver=true
check(S.request(F.player,{radio=true}),"acknowledged dispatch")
local ctx=S.current()
check(ctx.driverId=="sc-driver" and ctx.carSqlId==77 and ctx.seats["sc-follower"]==2 and ctx.playerSeat==1,"exact pair and party seats")
F.tick() check(ctx.phase=="board_driver","view acquired before driver boards")
S.step(F.driver,F.player,{}) F.tick() F.tick()
check(ctx.phase=="outbound" and F.drive~=nil and F.view=="pickup","empty outbound owns view")
local old=ctx.pickup
local roadside=SC.TaxiService.findRoadsideStop
SC.TaxiService.findRoadsideStop=function(at,search,accepts)
    if not search then return nil,nil,{} end
    return roadside(at,nil,accepts)
end
F.player.x=155
local pending,pendingReason=S.updatePickup({radio=true})
check(not pending and pendingReason=="pickup_finding_road" and ctx.pickup==old and ctx.updateRequested,
    "bounded search keeps the agreed point while its explicit update is pending")
F.tick()
check(ctx.pickup.x==155 and ctx.pickup~=old and not ctx.updateRequested,
    "one explicit update continues its search and changes the point only after delivery")
SC.TaxiService.findRoadsideStop=roadside F.tick()
old=ctx.pickup
local homeRoute=SC.ExpeditionRoute.planFromPoint
SC.ExpeditionRoute.planFromPoint=function() return nil,"no_route" end
local changed,why=S.updatePickup({radio=true})
check(not changed and why=="pickup_no_return_route" and ctx.pickup==old and F.drive~=nil,
    "pickup update reserves a real return route before changing the agreed point")
SC.ExpeditionRoute.planFromPoint=homeRoute
local deliver=SC.PickupRadio.deliver
SC.PickupRadio.deliver=function(...)
    local delivered,receipt=deliver(...)
    F.states[F.driver].commandSerial=5
    return delivered,receipt
end
local stale,staleReason=S.updatePickup({radio=true})
check(not stale and staleReason=="pickup_request_changed" and ctx.pickup==old,
    "an order changed during the native reply invalidates its stale update callback")
SC.PickupRadio.deliver=deliver F.states[F.driver].commandSerial=4
F.deliver=false F.player.x=160
check(not S.updatePickup({radio=true}) and ctx.pickup==old and F.drive~=nil,"failed update keeps agreed orders")
check(not S.cancel({radio=true}) and ctx.phase=="outbound","failed cancellation keeps driving")
F.deliver=true
local originalStop=SC.Driving.stop
SC.Driving.stop=function() return false,"pickup_waiting_for_stop" end
check(S.updatePickup({radio=true}) and ctx.pickup.x==160 and ctx.phase=="acquire_outbound",
    "delivered update is retained while the original car is still stopping")
F.tick()
check(ctx.phase=="acquire_outbound" and F.drive~=nil,"new route waits for release of the old wheel lease")
SC.Driving.stop=originalStop
F.tick() F.tick()
SC.ActionSupervisor={current=function() return {owner="medical"} end}
S.suspendForSurvival(F.driver,false)
check(ctx.phase=="held" and F.drive==nil,"an already active medical action stops the journey before decision ownership yields")
SC.ActionSupervisor=nil S.suspendForSurvival(F.driver,false)
check(S.retry({radio=true}),"medical hold has an explicit acknowledged retry") F.tick() F.tick()
F.arrive() F.tick()
check(ctx.phase=="waiting_board" and F.drive==nil and F.view==nil and F.reservation==ctx.requestId,"parked waiting releases wheel and visible view only")
check(not S.departHome(false),"cannot drive without booked player")
F.seat(F.player,1)
check(not S.departHome(false) and ctx.phase=="waiting_board","missing follower holds departure")
F.seat(F.follower,2)
F.snapGoal=true
check(S.depart({x=180,y=110,z=0},false),"local destination accepted with party seated")
check(ctx.destination.y==100,"map destinations use the reachable road stop")
F.snapGoal=nil
F.tick() F.tick()
check(ctx.phase=="ride" and F.drive.options.passenger==F.player and F.view==nil,"exact booked passenger lease in primary view")
local saved=S.export()
check(saved.state=="active" and saved.active.phase=="ride" and saved.active.restorePoint~=nil,"passenger journal has a restart anchor")
check(saved.active.actor==nil and saved.active.source==nil and saved.active.plan.vehicle==nil,"journal has no native object references")
F.arrive() F.tick()
check(ctx.phase=="drop_wait" and F.drive==nil,"drop-off waits for normal exits")
F.tick() check(ctx.phase=="drop_wait","never takes remaining passengers on empty return")
F.exit(F.player) F.tick() check(ctx.phase=="drop_wait","follower exit also required")
F.exit(F.follower) F.roadStop=true F.tick() F.tick() F.tick()
check(ctx.phase=="returning" and F.drive~=nil and F.view=="pickup" and F.drive.options.passenger==nil,"view reacquired before empty return")
F.arrive()
check(ctx.phase=="returning" and F.approaches==1,"road arrival continues towards the actual camp bay")
F.arrive() F.arrive() F.tick() F.roadStop=nil
check(ctx.phase=="exit_driver","original bay verified before exit")
S.step(F.driver,F.player,{}) F.tick()
F.driver.x,F.driver.y=100,100 F.tick() F.tick()
check(S.current() and S.current().phase=="finish" and F.detached=="sc-driver","native commit may detach before completing")
F.missing=true
F.tick()
check(S.current()==nil and F.claim==nil and F.reservation==nil,"remote completion releases all service authority")
F.missing=false
check(S.export().outcome.result=="returned" and S.export().preferred.carSqlId==77,"successful pair remembered")
local idle=S.export()
S.reset() check(S.restore(idle) and S.current()==nil,"idle journal round trip")
S.reset() check(S.restore(nil) and S.current()==nil,"old saves default to idle")
check(S.restore(saved),"passenger journal accepted")
F.tick() check(S.current().restoring==nil,"restoration joins exact driver")
S.reset()
saved.active.seats["sc-follower"]=1
check(not S.restore(saved) and S.current()==nil,"duplicate player seat quarantined atomically")
saved.active.seats["sc-follower"]=2 saved.active.driverId="unknown"
check(not S.restore(saved),"unowned driver journal rejected")
saved.active.driverId="sc-driver" saved.active.restorePoint.x=0/0
check(not S.restore(saved),"nonfinite restore anchor rejected")
F.player.x,F.player.y=150,100 F.exit(F.driver)
ready() check(S.request(F.player,{radio=true}),"second request") F.tick()
SC.Commands.peek(F.driver).commandSerial=5 F.tick()
check(S.current().phase=="held" and S.current().reason=="pickup_new_player_order","manual orders invalidate driving authority")
local manualDrive={manual=true}
F.drive=manualDrive F.missing=true
F.tick()
check(F.drive==manualDrive and S.step(F.driver,F.player,{})==nil
    and not S.ownsSeat(F.driver,F.car),"held pickup never stops or owns a later manual journey")
local relinquished=S.export()
check(relinquished.active.relinquished==true,"manual takeover survives the journal")
S.prepareReset() S.reset() F.drive=manualDrive
check(S.restore(relinquished),"manual takeover journal restores") F.tick()
check(S.current().relinquished and F.drive==manualDrive,"restoring relinquished view does not require or move the old car")
SC_TEST_REPORT="PICKUP_SERVICE_PASS checks="..tostring(F.checks)
