-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,MEDICAL_CONTEXT_TEST
local check=T.check
local inventory={}
local television={tv=true}
local radio={}
for _,item in ipairs({television,radio}) do
    function item:getContainer() return inventory end
    function item:getDeviceData() return {getIsTelevision=function() return self.tv==true end} end
end
function T.doctor:getInventory() return inventory end
function T.doctor:getPrimaryHandItem() return {weapon=true} end
function T.doctor:getSecondaryHandItem() return radio end
SC.GameplayUtil.instanceOf=function(item,kind) return kind=="Radio" and (item==radio or item==television) end
SC.GridControl={visible=function() return true end}
local selected
SC.GridRadio={request=function(player,item) selected=item return true,"Requested" end}
SC.TaxiBooking={checkRadio=function() return false end}
local function menuFor(items)
    local menu=T.menu() menu.addOptionOnTop=menu.addOption
    SC.UIContext.fillRadioContextMenu(0,menu,items)
    return menu
end
local menu=menuFor({radio})
local option=menu:getOptionFromName("EMMA: Grid report")
check(option~=nil,"equipped radio offers explicit EMMA contact without a taxi preset")
option.onSelect()
check(selected==radio,"secondary-hand radio stays selected when the primary hand holds a weapon")
check(menuFor({television}):getOptionFromName("EMMA: Grid report")==nil,"televisions cannot request EMMA")
SC.GridControl.visible=function() return false end
check(menuFor({radio}):getOptionFromName("EMMA: Grid report")==nil,"unsupported grid worlds hide the contact")
SC_TEST_REPORT="Grid radio inventory context: "..T.checks.." checks passed"
