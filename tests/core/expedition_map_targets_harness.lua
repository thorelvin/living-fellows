-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local T=SC.ExpeditionTargets
local scope="all_nearby"
local originalConfig=SC.Config.get
SC.Config.get=function(key,...) if key=="expeditionDestinationScope" then return scope end return originalConfig(key,...) end
local F=SC.ExpeditionPlacesFixture
local checks=0
local function check(value,message) checks=checks+1 assert(value,"map targets "..checks..": "..message) end
local known,visited=false,false
WorldMapVisited={getInstance=function() return {
    isKnown=function() return known end,isVisited=function() return visited end} end}
local actor={x=100,y=1000,getX=function(self)return self.x end,getY=function(self)return self.y end}
SC.GameplayUtil.position=function(a)return a.x,a.y,0 end
SC.GameplayUtil.loadedSquare=function() return nil end
SC.GameplayUtil.nowMs=function()return 1000 end
SC.BaseLife={isInside=function()return false end}
local grid=F.world:getMetaGrid()
local intersections,lookups=0,0
grid.getBuildingsIntersecting=function() intersections=intersections+1 error("manual query used departure scan") end
local originalAt=grid.getBuildingAt
grid.getBuildingAt=function(self,...) lookups=lookups+1 return originalAt(self,...) end
local zone={getType=function()return "Forest"end,getX=function()return 0 end,getY=function()return 0 end,
    getWidth=function()return 30000 end,getHeight=function()return 30000 end,contains=function()return true end}
grid.getZonesIntersecting=function()return F.list({zone})end
local bankX,bankY=0,0
SCBridge={mappedFishingBanks=function(_,x,y,radius)
    check(radius<=32,"shoreline lookup remains local regardless of trip length")
    return bankX..":"..bankY end,
    mappedFishingBankPlausible=function(_,x,y)return x==bankX and y==bankY end}
T.mapData={}
local function resolve(kind,distance,mode)
    local at={x=actor.x+distance,y=actor.y,z=0}
    bankX,bankY=at.x,at.y
    F.buildings[#F.buildings+1]=F.building(at.x-1,at.y-1,at.x+2,at.y+2,{"grocery"})
    local result,reason=T.resolveAtPoint(kind,at,T.context(actor,mode))
    F.buildings[#F.buildings]=nil
    return result,reason
end
for _,kind in ipairs({"scout","search","fish","wood"}) do
    for _,mode in ipairs({"road","straight","drive"}) do
        for _,distance in ipairs({200,201,1000,1001,5000,5001}) do
            for _,revealed in ipairs({false,true}) do
                known,visited=revealed,false
                local target,reason=resolve(kind,distance,mode)
                local expected=distance<=T.limit(mode) and (distance<=200 or revealed)
                check((target~=nil)==expected,kind.." "..mode.." "..distance.." known="..tostring(revealed).." reason="..tostring(reason))
                if target then
                    check(T.valid(target) and T.valid(T.copy(target)),"only plain valid targets leave the resolver")
                    if kind=="wood" then
                        check(#target.sites<=3 and #target.sites>0,"wood has bounded local alternatives")
                        for _,site in ipairs(target.sites) do
                            check(site.bounds.x1>=target.workBounds.x1 and site.bounds.x2<=target.workBounds.x2,
                                "logging alternatives remain inside selected work area")
                        end
                    end
                end
            end
        end
    end
end
check(intersections==0 and lookups>0,"distant buildings use point lookup without a departure-radius scan")
known,visited=false,true
check(resolve("scout",5000,"drive")~=nil,"physically visited terrain qualifies without the map-known flag")
visited=false
scope="known_only"
check(resolve("search",200,"road")==nil,"Known only also gates nearby unexplored buildings")
known=true
check(resolve("search",200,"road")~=nil,"map-revealed buildings qualify without loaded interiors")
scope="all_nearby"
local at={x=600,y=1000,z=0}
F.buildings[#F.buildings+1]=F.building(599,999,603,1003,{"grocery"})
local target=T.resolveAtPoint("search",at,T.context(actor,"drive"))
check(T.validate(target,T.context(actor,"road"))~=nil,"travel edits retain a compatible destination")
local forged=T.copy(target) forged.id="other"
check(T.validate(forged,T.context(actor,"road"))==nil,"forged stable identity does not select another building")
known=false
check(T.validate(target,T.context(actor,"road"))==nil,"dispatch rechecks forgotten map knowledge")
known=true
local before=T.fingerprint(target)
target.kind="scout"
check(T.fingerprint(target)~=before,"changing mission type invalidates the reviewed target")
target.kind="search"
local options={travelMode="road",turnHomeAfterHours=12,request={quantity=4,category="food"}}
local signature=T.reviewFingerprint(target,options,{{id="one"}})
check(signature~=T.reviewFingerprint(target,options,{{id="two"}}),"review binds exact crew")
options.request.quantity=8
check(signature~=T.reviewFingerprint(target,options,{{id="one"}}),"review binds requested supplies")
local wood=resolve("wood",1000,"drive")
check(T.matchesMission(wood,{kind="wood",wood={sites=wood.sites}}),"saved wood matches its work area")
local outside=T.copy(wood)
outside.workBounds.x2=outside.workBounds.x2+1
check(not T.valid(outside),"saved work bounds cannot expand the selected area")
wood.sites[1].bounds.x2=wood.workBounds.x2+1
check(not T.matchesMission(wood,{kind="wood",wood={sites=wood.sites}}),"reload refuses a patch escaping its selected area")
for _,bad in ipairs({true,12,"bad",{},{kind="wood",wood=true},{kind="wood",wood={sites=true}},
    {kind="wood",wood={sites={true}}},{kind="wood",wood={sites={{bounds=true}}}}}) do
    local okay,value=pcall(T.matchesMission,wood,bad)
    check(okay and value==false,"malformed saved woodland fails without throwing")
end

-- Real picker lifecycle with lightweight UI/native surfaces.
local M=SC.ExpeditionMap
SC.UI={text=function(key,...)return key end,wrapText=function(_,text)return{text}end}
local visible,accepted,resumed=true,0,0
local owner={setVisible=function(_,v)visible=v end,bringToTop=function()end}
local map={mapAPI={getZoomF=function()return 18 end},getWidth=function()return 1000 end,getHeight=function()return 800 end,
    removeChild=function()end}
function map:close() M.closed(self) end
ISWorldMap={IsAllowed=function()return true end,ShowWorldMap=function()ISWorldMap_instance=map end}
local draft={kind="search",mapTarget=T.copy(target)}
local valid=true
local function begin()
    return M.begin(owner,draft,function()return T.context(actor,"drive")end,
        function(chosen)accepted=accepted+1 draft.mapTarget=chosen end,
        function()resumed=resumed+1 end,function()return valid end)
end
check(begin() and not visible,"opening map suspends rather than destroys the owner")
map:close()
check(visible and accepted==0 and resumed==1 and T.fingerprint(draft.mapTarget)==T.fingerprint(target),
    "closing map restores the original draft without committing a selection")
check(begin(),"picker can reopen")
local context={options={}}
function context:addOption(label,_,callback)local row={label=label,callback=callback}self.options[#self.options+1]=row return row end
M.fillContext(map,context,at)
check(#context.options==1 and M.session.highlight,"right-click resolves and highlights the selected building")
context.options[#context.options+1]={name="Other mod",label="Other mod"}
M.fillContext(map,context,at)
check(#context.options==2 and context.options[1].name=="Other mod","repeated right-clicks replace owned entries and retain other menus")
table.remove(context.options,1)
local stale=context.options[1].callback
map:close()
check(begin(),"another picker session can begin")
stale()
check(accepted==0 and M.session~=nil,"an old menu cannot commit into a new picker session")
context.options={}
M.fillContext(map,context,at)
context.options[1].callback()
check(accepted==1 and visible and M.session==nil,"selection validates then returns exactly once")
check(begin(),"picker opens before owner disposal")
valid=false
map:close()
check(M.session==nil and not visible,"disposed owners are not resurrected on map closure")
print("EXPEDITION_MAP_TARGETS_PASS checks="..checks)
SC_TEST_REPORT="EXPEDITION_MAP_TARGETS_PASS checks="..checks
