-- SPDX-License-Identifier: MIT
SurvivorCompanion = { GameplayUtil = {}, Registry = {}, NativeActions = {}, Navigation = {}, BaseLife = {} }
local SC, F = SurvivorCompanion, { now = 1000, squares = {}, lines = {}, created = 0, fires = 0 }
CalebFixture = F
local U, N = SC.GameplayUtil, SC.NativeActions
function U.call(o, method, ...)
    if not o or type(o[method]) ~= "function" then return nil, false end
    return o[method](o, ...), true
end
function U.position(o) if o then return o.x, o.y, o.z or 0 end end
function U.gridSquare(x,y,z)
    local key = x .. ":" .. y .. ":" .. z
    if F.unloaded == key then return nil end
    if not F.squares[key] then
        local s = { x=x,y=y,z=z,bodies={} }
        function s:isOutside() return not self.inside end
        function s:getRoom() return self.inside and {} or nil end
        function s:getBuilding() return self.inside and {} or nil end
        function s:getTree() return self.tree end
        function s:haveFire() return self.fire == true end
        F.squares[key] = s
    end
    return F.squares[key]
end
function U.squareOf(o) return U.gridSquare(math.floor(o.x),math.floor(o.y),o.z or 0) end
function U.modData(o) return o.data end
function U.isClearActorSpawnSquare(s) return s and not s.blocked end
function U.sameFloor(a,b) return (a.z or 0)==(b.z or 0) end
function U.distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
function U.canSee() return F.visible ~= false end
function U.isDead(a) return a.dead == true end
function U.instanceOf(o,kind) return o.kind == kind end
function U.squareStaticMovingObjects(s,callback,limit)
    for i=1,math.min(#s.bodies,limit) do if callback(s.bodies[i])==false then break end end
end
function U.nowMs() return F.now end
function U.movementStateBlocker() return F.pickupLocked and "movement_locked" or nil end
function U.say(a,line) F.lines[#F.lines+1]=line end
function U.stop() return true end
function SC.BaseLife.isInside(s) return s.camp end
function SC.Registry.byId() return {actor=F.actor} end
function N.isDraggingCorpse(a) return a.target ~= nil end
function N.dragSessionActive() return F.session == true end
function N.isWorkActive() return F.busy == true end
function N.finishWork() return not F.busy end
function N.settleDrag() return true end
function N.cancelWork() F.busy=false; return true end
function N.releaseCorpse(a)
    if a.target then
        local b=a.target
        b.x,b.y,b.z=a.x,a.y,a.z
        local s=U.squareOf(b); s.bodies[#s.bodies+1]=b
        a.target=nil
    end
    return true
end
function SC.Navigation.request(a,s)
    if F.blockRoute then return false,"blocked" end
    a.x,a.y,a.z=s.x+.5,s.y+.5,s.z
    if a.target then a.target.x,a.target.y=a.x-0.4,a.y end
    return true
end
function U.move(a,_,options)
    if options.action=="grab_body" then
        local b=options.body; local s=U.squareOf(b)
        for i=#s.bodies,1,-1 do if s.bodies[i]==b then table.remove(s.bodies,i) end end
        a.target=b
    elseif options.action=="drop_body" then N.releaseCorpse(a) end
    return true
end
function createRandomDeadBody(s)
    F.created=F.created+1
    if F.failCreate then return nil end
    local b={kind="IsoDeadBody",x=s.x+.5,y=s.y+.5,z=s.z,data={}}
    function b:setReanimateTime(t) self.reanimate=t end
    s.bodies[#s.bodies+1]=b; return b
end
function getCell() return F.squares end
IsoFireManager={ StartFire=function(_,s) s.fire=true; F.fires=F.fires+1 end }
BloodBodyPartType={UpperArm_L=1,LowerLeg_R=2}
function F.reset()
    F.now,F.squares,F.lines,F.created,F.fires=1000,{}, {},0,0
    F.visible,F.failCreate,F.busy,F.blockRoute,F.pickupLocked,F.session=true,false,false,false,false,false
    F.actor={x=8.5,y=10.5,z=0,holes=0}
    function F.actor:getGrapplingTarget() return self.target end
    function F.actor:addHole() self.holes=self.holes+1 end
    function F.actor:SetOnFire() self.burning=true end
    function F.actor:isOnFire() return self.burning==true end
    F.player={x=8.5,y=12.5,z=0}
    F.group={id="caleb",members={{actorId="caleb-actor"}},oddball={
        id="family_pyre_caleb_hensley",stage="unmet",
        site=SC.OddballCaleb.siteFor(U.gridSquare(10,10,0),F.player,true)}}
end
