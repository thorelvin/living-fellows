-- SPDX-License-Identifier: MIT
local SC, checks = SurvivorCompanion, 0
local function check(value, message) checks=checks+1; assert(value,message) end
local primary, companion, dead, foreign = {}, {}, {}, {}
local secondary = companion
local owned = {[companion]=true,[dead]=true}
function getSpecificPlayer(index) return index==0 and primary or index==1 and secondary or nil end
SCBridge = {isCompanion=function(actor) return owned[actor]==true end}
UIManager={UI={}}
local function panel(kind, actor)
    local value={Type=kind,player=actor,visible=true,keyCalls=0}
    function value:setVisible(on) self.visible=on end
    function value:removeFromUIManager()
        for i=#UIManager.UI,1,-1 do if UIManager.UI[i]==self then table.remove(UIManager.UI,i) end end
    end
    function value:handleKey()
        self.keyCalls=self.keyCalls+1
        self.visible=true
        UIManager.UI[#UIManager.UI+1]=self
    end
    UIManager.UI[#UIManager.UI+1]=value
    return value
end
local primaryZone=panel("ISDesignationZonePanel",primary)
local primaryBar=panel("SSBar",primary)
local activeBar=panel("SSBar",companion)
local deadBar=panel("SSBar",dead)
local foreignBar=panel("SSBar",foreign)
local unknown=panel("UnrelatedWindow",companion)
SC.ViewUI.remember(dead); owned[dead]=nil
local zone=panel("ISDesignationZonePanel",companion)
local data={zoneUI=zone}
function getPlayerData(index) return index==1 and data or nil end
function getPlayerZoneUI(index) return index==0 and primaryZone or data.zoneUI end
ISDesignationZonePanel={instance=zone}
check(SC.ViewUI.cleanup()==1 and not deadBar.visible,"remembered dead actor panel removed; active view retained")
check(activeBar.visible and zone.visible and foreignBar.visible and unknown.visible,"active/foreign/unknown panels untouched")
secondary=nil
check(SC.ViewUI.cleanup()==2,"both known panels retire together despite list compaction")
check(not activeBar.visible and not zone.visible,"released panels hidden")
check(data.zoneUI==nil and ISDesignationZonePanel.instance==primaryZone,"only stale vanilla aliases detached")
local count=#UIManager.UI
activeBar:handleKey(1); activeBar:handleKey(1); deadBar:handleKey(1)
check(#UIManager.UI==count and activeBar.keyCalls==0 and deadBar.keyCalls==0,"retained hotkeys cannot reopen retired panels")
check(primaryBar.visible and foreignBar.visible and unknown.visible,"main player and unrelated windows survive release")
check(SC.ViewUI.cleanup()==0,"cleanup is idempotent")
primaryBar:handleKey(1)
check(primaryBar.keyCalls==1,"main player hotkeys still work")
activeBar.player=foreign; activeBar:handleKey(1)
check(activeBar.keyCalls==1,"legitimate panel rebinding retains the original method")
print("VIEW_UI_PASS checks="..checks)
