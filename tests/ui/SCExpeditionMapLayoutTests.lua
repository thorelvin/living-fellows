-- SPDX-License-Identifier: MIT
local SC,F=SurvivorCompanion,BasePolicyFixture
local M,T=SC.ExpeditionMap,SC.ExpeditionTargets
local oldText,oldButton=SC.UI.text,ISButton
local oldResolve=T.resolveAtPoint
T.resolveAtPoint=function()error("map render must not query destinations")end
SC.UI.text=function(key,...)
    if key=="UI_SC_Map_Instructions" then return "Scout a building: right-click a location. Drag to pan; scroll to zoom. Range: 5000 tiles. Beyond 200 tiles, the location must be visited or revealed on your map." end
    if key=="UI_SC_Map_TargetSummary" then return "Selected woodland near Oak Street | 4895 tiles | Known on your map; conditions checked on arrival" end
    return key
end
ISButton={new=function(_,x,y,w,h)
    return {x=x,y=y,width=w,height=h,initialise=function()end,
        setX=function(self,value)self.x=value end,setY=function(self,value)self.y=value end}
end}
local checks=0
for _,size in ipairs({{1280,720},{1366,768},{1920,1080},{2560,1440}}) do
    for _,fontHeight in ipairs({16,24,32}) do
        F.fontHeight=fontHeight
        local rectangles,children={},{}
        local map={width=size[1],height=size[2]}
        function map:getWidth()return self.width end
        function map:getHeight()return self.height end
        function map:addChild(child)children[#children+1]=child end
        function map:removeChild()end
        function map:drawRect(x,y,w,h)rectangles[#rectangles+1]={x=x,y=y,width=w,height=h}end
        function map:drawText()end
        function map:drawLine2(x,y,x2,y2)assert(x==x and y==y and x2==x2 and y2==y2)end
        map.mapAPI={worldToUIX=function(_,x,y)return (x-y)*0.05+map.width/2 end,
            worldToUIY=function(_,x,y)return (x+y)*0.025+map.height/2 end}
        map.keyUI={isVisible=function()return true end,getX=function()return 10 end,getWidth=function()return 300 end}
        map.symbolsUI={isVisible=function()return true end,getX=function()return map.width-300 end}
        local actor={getX=function()return 100 end,getY=function()return 100 end}
        M.session={map=map,owner={},kind="wood",context=function()return T.context(actor,"drive")end,
            highlight={anchor={x=110,y=110,z=0},workBounds={x1=78,y1=78,x2=142,y2=142},label="Woodland",distance=4895,mapKnown=true}}
        M.render(map)
        assert(rectangles[1].x>=322 and rectangles[1].x+rectangles[1].width<=map.width-312,
            "instruction banner leaves the native legend and symbols visible")
        local back=children[1]
        assert(back and back.x>=0 and back.y>=0 and back.x+back.width<=map.width and back.y+back.height<=map.height,
            "Back control remains on screen")
        local card=rectangles[#rectangles]
        assert(card.x>=0 and card.x+card.width<=map.width and card.y+card.height<=back.y,
            "wrapped selection card fits above the controls")
        M.render(map)
        assert(#children==1,"redraw reuses its control tree")
        M.reset()
        checks=checks+1
    end
end
T.resolveAtPoint,SC.UI.text,ISButton=oldResolve,oldText,oldButton
F.fontHeight=16
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Map layout: "..checks.." resolution/font cases, rotated coordinates and query-free redraw PASS"
