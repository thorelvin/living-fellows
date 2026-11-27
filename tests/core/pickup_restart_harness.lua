-- SPDX-License-Identifier: MIT
local F,SC=PICKUP,LivingFellows
local S,check=SC.PickupService,PICKUP.check
check(S.beginPreview(F.player,{radio=true}),"preparation opens") F.tick()
check(S.request(F.player,{radio=true}),"initial accepted order")
local basis=S.export()
S.prepareReset() S.reset()
for _,name in ipairs({"acquire","board_driver","outbound","pickup_handoff","waiting_board",
    "ride_start","ride","drop_wait","returning","parked","exit_driver","camp_arrival","finish","held"}) do
    local saved=S.copy(basis)
    saved.active.phase=name
    saved.active.destination={x=180,y=100,z=0}
    if name=="held" then saved.active.resumePhase="outbound" end
    F.drive=nil F.detached=nil
    if F.driver.vehicle then F.exit(F.driver) end
    if F.player.vehicle then F.exit(F.player) end
    if F.follower.vehicle then F.exit(F.follower) end
    if name=="ride" or name=="ride_start" or name=="waiting_board" or name=="drop_wait" then F.seat(F.player,1) end
    check(S.restore(saved),"journal accepts saved "..name)
    F.tick()
    local ctx=S.current()
    check(ctx~=nil and not ctx.restoring,"owned driver restored for "..name)
    check(ctx.driverId=="sc-driver" and ctx.carSqlId==77 and ctx.playerSeat==1
        and ctx.seats["sc-follower"]==2,"identity and seats retained for "..name)
    if name=="finish" or name=="camp_arrival" or name=="exit_driver" or name=="parked" or name=="drop_wait" then
        check(ctx.phase~="board_driver" and F.driver.vehicle==nil,"on-foot camp/wait phase never invents boarding: "..name)
    elseif name=="held" then check(ctx.phase=="held" and not F.drive,"held trip never restarts by loading")
    else
        check(ctx.phase=="board_driver","saved native seat restores through normal boarding: "..name)
        S.step(F.driver,F.player,{}) F.tick()
        check(F.car:getDriver()==F.driver,"exact driver reboards for "..name)
    end
    S.prepareReset() S.reset()
end
local dead=S.copy(basis) dead.active.driverDead=true
check(S.restore(dead) and S.current()==nil and S.export().outcome.result=="driver_lost",
    "saved dead driver produces an outcome instead of resurrection")
S.reset()
local invalid=S.copy(basis) invalid.active.slotSqlId=1
check(not S.restore(invalid) and S.current()==nil,"primary SQL slot cannot be borrowed on restore")
local finishing=S.copy(basis)
finishing.active.phase,finishing.active.resumePhase="held","finish"
F.detached=nil F.missing=false F.drive=nil
if F.driver.vehicle then F.exit(F.driver) end
check(S.restore(finishing),"held finish restores") F.tick()
check(S.retry({radio=true}) and S.current().phase=="finish" and F.driver.vehicle==nil,
    "retrying camp save never reboards the empty parked car")
S.prepareReset() S.reset()
local warming=SC.PickupJourney.warm
SC.PickupJourney.warm=function() return false,"pickup_loading_camp" end
check(S.restore(basis),"loading restart accepted") F.tick()
F.time=F.time+90001 F.tick()
check(S.current().phase=="held" and S.current().restoreHeld and S.current().restoring,
    "unavailable remote world reaches a bounded technical hold")
local frozen=S.export()
S.prepareReset() S.reset()
check(S.restore(frozen),"loading hold persists") F.tick()
check(S.current().restoreHeld and S.current().phase=="held","restart cannot silently retry a loading hold")
F.deliver=false
check(S.retry(nil) and S.current().restoring and not S.current().restoreHeld,
    "technical retry reloads accepted orders without sending a new radio command")
SC.PickupJourney.warm=warming F.deliver=true F.tick()
check(not S.current().restoring,"technical retry can recover the same driver")
S.step(F.driver,F.player,{}) F.tick() F.tick() F.tick()
F.time=F.time+30001 F.tick()
check(S.current().phase=="held" and S.current().reason=="pickup_route_blocked" and not F.drive,
    "a native route that keeps reporting following without physical progress reaches a bounded safe hold")
SC_TEST_REPORT="PICKUP_RESTART_PASS checks="..tostring(F.checks)
