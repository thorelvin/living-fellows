-- SPDX-License-Identifier: MIT
local SC, checks = SurvivorCompanion, 0
local function check(value,message) checks=checks+1;assert(value,message) end
local now, fetched, action = 1000, 0, nil
local actor={inventory={items={}}}
local runtime={}
local assessment={thirsty=true,thirst=0.6,hunger=0.2}
function getGameTime() return nil end
Fluid={Water="Water",TaintedWater="TaintedWater"}
SC.GameplayUtil={
    call=function(object,method,...)
        if not object or type(object[method])~="function" then return nil,false end
        return object[method](object,...),true
    end,
    inventory=function(value) return value.inventory end,
    itemWeight=function() return 1 end,
    actorState=function() return runtime end,
    each=function(items,limit,callback)
        for i=1,math.min(#items,limit) do if callback(items[i])==false then break end end
    end,
    instanceOf=function() return false end,
    hasMethod=function(value,method) return type(value[method])=="function" end,
    nowMs=function() return now end,
    config=function() return nil end,
    isValidActor=function() return true end,
    clamp=function(value,low,high) return math.max(low,math.min(high,value)) end,
    move=function(_,_,options) action=options; return true,options.action end,
    gridSquare=function() error("trip unexpectedly searched world supplies") end,
}
SC.PersonalItems={isProtected=function(item) return item.protected==true end}
SC.CleaningSupplies={containsCleaner=function(item) return item.cleaner==true end}
SC.Encounter={takePlayerSupply=function() fetched=fetched+1;return "in_progress","camp_fetch" end}
SC.Needs.assess=function() return assessment end
SC.NativeActions=nil
local water={}
function water:getFluidContainer()
    return {getAmount=function() return 0.5 end,getCapacity=function() return 1 end,
        isEmpty=function() return false end,isTainted=function() return false end,
        isPoisonous=function() return false end,canPlayerEmpty=function() return true end,
        contains=function(_,fluid) return fluid==Fluid.Water end,
        getComponentAmount=function(_,fluid) return fluid==Fluid.Water and 0.5 or 0 end}
end
local bag={getInventory=function() return {items={water}} end}
actor.inventory.items={bag}
check(SC.Needs.carriedSuppliesAvailable(actor,assessment),"nested carried water is eligible")
water.cleaner=true
check(not SC.Needs.carriedSuppliesAvailable(actor,assessment),"cleaner-dominant or water-dominant cleaning mixtures stay excluded")
water.cleaner=nil;water.protected=true
check(not SC.Needs.carriedSuppliesAvailable(actor,assessment),"protected drinks cannot admit a consumption errand")
water.protected=nil
check(not SC.Needs.update(actor,nil,runtime,{expeditionTravel=true}) and action==nil
    and fetched==0,"travelling defers routine drinking")
check(SC.Needs.update(actor,nil,runtime,{expeditionMember=true}) and action.action=="drink_item"
    and action.item==water and fetched==0,"a stopped trip drinks its real carried water without a camp/world route")
actor.inventory.items={}
assessment={hungry=true,hunger=0.76,thirst=0.2}
check(not SC.Needs.carriedSuppliesAvailable(actor,assessment),"empty trip inventory has no routine meal")
check(not SC.Needs.update(actor,nil,runtime,{expeditionTravel=true}) and fetched==0,"routine trip hunger does not start a camp errand")
assessment.emergency=true;assessment.hunger=0.9
check(SC.Needs.update(actor,nil,runtime,{expeditionTravel=true}) and fetched==1,"emergency hunger retains access to supplies")
assessment.emergency=false;assessment.hunger=0.76
check(SC.Needs.update(actor,nil,runtime) and fetched==2,"ordinary camp hunger still fetches food")
local food={getHungerChange=function() return -0.3 end}
actor.inventory.items={food}
check(SC.Needs.carriedSuppliesAvailable(actor,assessment),"safe carried food admits routine needs")
action=nil
check(not SC.Needs.update(actor,nil,runtime,{expeditionTravel=true}) and action==nil,
    "travelling defers routine meals")
check(SC.Needs.update(actor,nil,runtime,{expeditionMember=true}) and action.action=="eat_food"
    and action.item==food and fetched==2,"a stopped trip consumes the same real carried food")
local large={items={}}
for index=1,300 do large.items[index]={} end
large.items[300]=water
actor.inventory=large;assessment={thirsty=true}
check(not SC.Needs.carriedSuppliesAvailable(actor,assessment),"inventory discovery stays bounded")
actor.inventory.items={{getFluidContainer=function() error("unavailable mod container") end},water}
check(SC.Needs.carriedSuppliesAvailable(actor,assessment),"an unreadable mod container does not hide later usable supplies")
print("NEEDS_TRIP_PASS checks="..checks)
