-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local S,T=SC.TerminalServices,SC.ExpeditionTargets
local checks=0
local function check(value,message)checks=checks+1 assert(value,"terminal map "..checks..": "..message)end
local actor={getX=function()return 100 end,getY=function()return 100 end,isDead=function()return false end}
local record={id="crew",actor=actor}
SC.Registry={byId=function(id)return id=="crew" and record or nil end}
SC.Commands={describe=function()return {recruited=true,available=true,alive=true}end}
SC.BaseLife={active=function()return{id="camp"}end,isInside=function()return true end}
SC.RadioEndpoints={station=function()return{}end}
local target={version=1,kind="search",id="120:100:130:110",label="Store",anchor={x=125,y=105,z=0}}
local realValidate=T.validate
T.validate=function(value)
    if value.id~=target.id then return nil,"map_target_changed" end
    return value
end
local previews=0
SC.ExpeditionPrototype={current=function()return nil end,
    previewMapTarget=function(_,value) previews=previews+1 check(value.id==target.id,"review uses resolved map target")return{distance=25}end}
local window={object={},player={},system={locked=false},menuPage="expedition_plan",
    stationDraft={kind="search",travelMode="road",quantity=4,category="food",hours=4,crew={"crew"}},
    setFocusMode=function(self,mode)self.focusMode=mode end,
    startReply=function(self,reply)self.reply=reply end}
SC.Terminal={window=window,present=function()return true end,near=function()return true end,powered=function()return true end}
local pending
SC.ExpeditionMap={reason=function(value)return value end,begin=function(owner,draft,context,accept,resume,valid)
    pending={owner=owner,draft=draft,context=context,accept=accept,resume=resume,valid=valid}
    return true
end}
local function input(action,value)return S.input(window,"",{serviceAction=action,serviceValue=value})end
check(input("map_pick") and pending.owner==window and pending.draft==window.stationDraft,"station opens picker with its existing session")
check(pending.context().actor==actor and pending.valid(),"picker resolves current selected crew and terminal access")
pending.accept(target)
check(window.stationDraft.mapTarget.id==target.id and window.menuPage=="station_review" and previews==1,
    "selection returns to the station review with its target intact")
check(window.stationReviewed.mapFingerprint==T.fingerprint(target),"confirmation binds the full target fingerprint")
input("cycle","kind")
check(window.stationDraft.kind=="scout" and window.stationDraft.mapTarget.kind=="scout"
    and window.stationDraft.placeId==target.id and window.stationReviewed==nil,
    "Scout/Search editing retains the building and invalidates review")
window.stationDraft.kind="search"
window.stationDraft.mapTarget.kind="search"
window.stationDraft.hours=12
input("cycle","hours")
check(window.stationDraft.hours==24,"station offers the 24-hour departure deadline")
window.stationDraft.kind="wood"
input("places")
check(window.stationDraft.mapTarget==nil and window.stationDraft.placeId==nil,
    "automatic woodland selection explicitly leaves manual mode")
window.closed=true
check(not pending.valid(),"closed terminal cannot receive a stale map selection")
T.validate=realValidate
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; EMMA map picker: "..checks.." checks passed"
