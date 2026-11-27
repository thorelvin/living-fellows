-- SPDX-License-Identifier: MIT
-- Feed the real camp summary from the preceding fixture to the normal panel.
local SC, summary=LivingFellows,SC_TEST_STAFFING_VIEW
SC.BaseLife.summary=function() return summary end
SC.BaseLife.blueprintsVisible=function() return false end
SC.BaseLife.canRemoveZone=function() return false,"last_base_area" end
local detail=BasePolicyFixture.classes.SCUIDetail:new(0,0,450,400,{})
local function skip(_,_,y) return y end
detail.addMoreNavigation,detail.addSection=skip,skip
detail.buildBaseWatch,detail.addBasePolicySelector=skip,skip
detail.addBaseToggle,detail.buildProductionSection=skip,skip
detail.addBaseManagementAction=skip
local visible={}
function detail:addInformationLine(_,y,key,line)
    if key=="UI_SC_Base_StaffingRow" then visible[#visible+1]=line end
    return y
end
detail:buildBase(ISPanel:new(0,0,450,400))
local lines=table.concat(visible,"\n")
assert(#visible==17 and not lines:find("sc%-") and lines:find("Morgan Reed",1,true) and lines:find("Ellis West",1,true),
    "Staffing renders the sixteen living recruits and named dormant farmer without a dead ID")
SC_TEST_REPORT="CAMP_RESIDENT_CONSUMERS_PASS checks="..(SC_TEST_ROSTER_CHECKS+1)
SC_TEST_STAFFING_VIEW,SC_TEST_ROSTER_CHECKS=nil,nil
