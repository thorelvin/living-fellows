-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,MEDICAL_CONTEXT_TEST
local check=T.check
local restoreNative=T.installNativeMenus()
local inventory={}
local television={tv=true,container=inventory}
local radio={container=inventory}
local replacement={container=inventory}
for _,item in ipairs({television,radio,replacement}) do
    function item:getContainer() return self.container end
    function item:getDeviceData() return {getIsTelevision=function() return self.tv==true end} end
end
function T.doctor:getInventory() return inventory end
function T.doctor:getPrimaryHandItem() return {weapon=true} end
local heldRadio=radio
function T.doctor:getSecondaryHandItem() return heldRadio end
local nativeRadio=radio
function T.doctor:getEquipedRadio() return nativeRadio end
SC.GameplayUtil.instanceOf=function(item,kind)
    return kind=="Radio" and (item==radio or item==television or item==replacement)
end
SC.GridControl={visible=function() return true end}
local selected
SC.GridRadio={request=function(player,item) selected=item return true,"Requested" end}
SC.TaxiBooking={checkRadio=function() return false end}
local mission,orders
SC.ExpeditionPrototype={current=function() return mission end,
    sendRadioOrder=function(player,command,value)
        orders={player=player,command=command,value=value} return true
    end}
local function find(menu,key,direct)
    for _,option in ipairs(menu.options) do
        if option.scMenuKey==key or option.name==key then return option,menu end
        local child=option.subOption and menu:getSubMenu(option.subOption)
        if child and not direct then
            local found,parent=find(child,key)
            if found then return found,parent end
        end
    end
end
local function menuFor(items)
    local menu=T.nativeMenu() T.nativeRoot=menu
    SC.UIContext.fillRadioContextMenu(0,menu,items)
    return menu
end
local menu=menuFor({radio})
local option,parent=find(menu,"radio.grid")
check(option~=nil,"equipped radio offers explicit EMMA contact without a taxi preset")
check(find(menu,"radio",true) and parent~=menu and not find(menu,"radio.grid",true),
    "EMMA contact stays within the populated Radio services menu")
option.onSelect()
check(selected==radio,"secondary-hand radio stays selected when the primary hand holds a weapon")
selected=nil heldRadio=replacement
check(option.onSelect()==false and selected==nil,
    "an old EMMA action cannot dispatch through a different equipped radio")
heldRadio=radio radio.container={}
check(option.onSelect()==false and selected==nil,
    "a radio no longer in the player's inventory cannot use a retained action")
radio.container=inventory
check(find(menuFor({television}),"radio.grid")==nil,"televisions cannot request EMMA")
SC.GridControl.visible=function() return false end
check(find(menuFor({radio}),"radio.grid")==nil,"unsupported grid worlds hide the contact")
SC.GridControl.visible=function() return true end
mission={scout={kind="search",search=true,phase="outbound"}}
local routine=menuFor({radio})
check(find(routine,"radio.progress") and find(routine,"radio.return")
    and not find(routine,"radio.progress",true) and not find(routine,"radio.return",true),
    "routine expedition progress and recall stay grouped as radio services")
mission.scout.pause={reported=true}
local pending=menuFor({radio})
local hold=find(pending,"radio.answer.hold_position",true)
check(hold and find(pending,"radio.answer.push_on",true)
    and find(pending,"radio.answer.return",true) and not find(pending,"radio.return"),
    "a reported expedition decision exposes direct Hold, Push and Return responses")
hold.onSelect()
check(orders and orders.player==T.doctor and orders.command=="expedition_decision"
    and orders.value=="hold_position", "a direct decision dispatches its exact existing radio order")
orders=nil heldRadio=replacement
check(hold.onSelect()==false and orders==nil,"a retained pending response rejects a changed equipped device")
heldRadio=radio
local capturedMission=mission
mission={scout={kind="search",search=true,phase="outbound",pause={reported=true}}}
check(hold.onSelect()==false and orders==nil,
    "a retained decision for mission A cannot issue an order to replacement mission B")
mission=capturedMission nativeRadio=replacement
check(hold.onSelect()==false and orders==nil,
    "a retained expedition action rejects a native getEquipedRadio identity mismatch")
nativeRadio=radio
mission=nil
SC.OddballDistressRadio={replyOptions=function() return {{groupId="eli",label="Reply to Eli"}} end}
local distress=menuFor({radio})
check(find(distress,"radio.distress.eli",true)~=nil,
    "a pending distress reply remains directly accessible beside radio services")
SC.OddballDistressRadio=nil
restoreNative()
SC_TEST_REPORT="Grid radio inventory context: "..T.checks.." checks passed"
