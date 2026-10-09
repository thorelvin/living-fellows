-- Focused native-boundary simulation for the four final authored encounters.
local SC=SurvivorCompanion
local U={}
SC.GameplayUtil=U
local now,hour=1000,240
function getGameTime() return {getWorldAgeHours=function() return hour end} end
BloodBodyPartType={FromIndex=function(i) if i<17 then return i end end}
local checks=0
local function check(value,message)
    checks=checks+1
    assert(value,"final four "..checks..": "..message)
end
local function inventory()
    local v={items={}}
    function v:Remove(item)
        for i,other in ipairs(self.items) do
            if other==item then table.remove(self.items,i);item.container=nil;return end
        end
    end
    return v
end
local function add(inv,kind)
    local item={kind=kind,container=inv,data={}}
    function item:getContainer() return self.container end
    function item:setName(name) self.name=name end
    function item:getModData() return self.data end
    function item:setFavorite(value) self.favorite=value end
    function item:isFavorite() return self.favorite==true end
    inv.items[#inv.items+1]=item
    return item
end
function U.call(object,method,...)
    local f=object and object[method]
    if type(f)~="function" then return nil,false end
    return f(object,...),true
end
function U.inventory(a) return a and a.inv end
function U.inventoryItemsDeep(inv) return inv.items end
function U.addItem(inv,kind) return add(inv,kind) end
function U.itemType(item) return item.kind end
function U.modData(item) return item.data end
function U.idOf(a) return a and a.id end
function U.each(items,limit,callback)
    for index=1,math.min(#items,limit) do
        if callback(items[index],index)==false then break end
    end
end
function U.transferItemVerified(source,target,item)
    if not source or not target or item.container~=source then return false end
    if target.rejectType==item.kind then return false end
    source:Remove(item)
    target.items[#target.items+1]=item
    item.container=target
    return true
end
function U.position(a) return a.x,a.y,a.z end
function U.distance(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
function U.canSee() return true end
function U.isValidActor(a) return a~=nil end
function U.say(a,line) a.lines[#a.lines+1]=line;return true end
function U.nowMs() return now end
function U.config() return true end
function U.instanceOf(object,class) return object.class==class end
local door={class="IsoDoor",open=false,locked=true}
function door:IsOpen() return self.open end
function door:setLocked(value) self.locked=value end
function door:ToggleDoor() if not self.locked then self.open=not self.open end end
local square={objects={door}}
function square:getObjects() return self.objects end
function U.gridSquare(x,y,z)
    if x==10 and y==10 and z==-1 then return square end
end
SC.NativeList={get=function(list,index) return list[index+1] end}
local records={}
SC.Registry={byId=function(id) return records[id] end}
SC.Factions={
    adjustStanding=function(id,amount) return true end,
    forceStanding=function(id,standing)
        for _,r in pairs(records) do
            if r.group and r.group.id==id then r.group.standing=standing end
        end
        return true
    end,
    list=function() return {} end,
}
SC.FactionRecruitment={ask=function() return true end,
    startTrial=function() return true end}
SC.OddballAnimals={find=function() end}
local function actor(id,x,y,z)
    local a={id=id,x=x,y=y,z=z,inv=inventory(),lines={}}
    function a:setPrimaryHandItem(item) self.hand=item end
    function a:getHumanVisual() return self.visual end
    local r={actor=a,identity={}}
    records[id]=r
    return a,r
end
local function group(id,a,r,site)
    local g={id="group-"..id,standing="Wary",
        oddball={id=id,site=site or {}},members={{actorId=a.id}}}
    r.group=g
    return g
end
local player=actor("player",11,10,-1)
player.visual={blood=0.4,dirt=0.2}
function player.visual:getBlood() return self.blood end
function player.visual:getDirt() return self.dirt end

local gordon,gr=actor("gordon",10,10,-1)
local gg=group("gordon_pettibone",gordon,gr,
    {bunkerDoor={x=10,y=10,z=-1,objectIndex=0},
        bunkerOutside={x=11,y=10,z=-1}})
check(SC.OddballGordon.onSpawn(gg,gordon),"real pantry seeded")
check(#gordon.inv.items==13,"twelve cans and pistol")
check(SC.OddballGordon.canTalkThroughSlot(gg,player),"closed cellar slot")
check(not SC.OddballGordon.action(gg,"decon",player),"blood blocks opening")
player.visual.blood,player.visual.dirt=0.05,0.04
check(SC.OddballGordon.action(gg,"decon",player),"washing opens cellar")
check(door.open and gg.oddball.decontaminated,"real door opened")
for _=1,3 do
    add(player.inv,"Base.Battery")
    check(SC.OddballGordon.action(gg,"trade",player),"finite pantry trade")
end
check(gg.standing=="Trusted" and SC.OddballGordon.canRecruit(gg),
    "three real trades earn trust")

player.x,player.y,player.z=20,20,0
local morton,mr=actor("morton",20,20,0)
local mg=group("morton_buster",morton,mr,
    {chair={x=20,y=20,z=0,objectIndex=0}})
check(SC.OddballMorton.onSpawn(mg,morton),"real doll equipped")
check(morton.hand and morton.hand.kind=="Base.Doll","Buster in hand")
for day=1,3 do
    hour=day*24
    check(SC.OddballMorton.action(mg,"visit",player),"new day visit")
end
check(mg.oddball.stage=="choice","dark choice after visits")
check(SC.OddballMorton.action(mg,"refuse",player),"keep pair")
check(SC.OddballMorton.canRecruit(mg),"pair recruitable")
local second,sr=actor("morton2",20,20,0)
local sg=group("morton_buster",second,sr)
SC.OddballMorton.onSpawn(sg,second)
sg.oddball.stage="choice"
check(SC.OddballMorton.action(sg,"take_buster",player),"doll transferred")
check(sg.oddball.stage=="silent" and not SC.OddballMorton.canRecruit(sg),
    "taking doll silences performer")

local dancer,dr=actor("stage-dancer",21,20,0)
local dancerGroup=group("sleeping_it_off",dancer,dr)
local oldList=SC.Factions.list
SC.Factions.list=function() return {dancerGroup} end
SC.NativeList.size=function(list) return #list end
local costume={}
function dancer:getWornItems() return costume end
mg.oddball.stage="performing"
local function hasRoast(options)
    for _,option in ipairs(options) do
        if option.id=="roast" then return true end
    end
    return false
end
check(not hasRoast(SC.OddballMorton.menuOptions(mg,player)),
    "Buster does not roast a dancer after the costume is removed")
local suit=add(dancer.inv,"Base.BunnySuitPink")
costume[1]={getItem=function() return suit end}
check(hasRoast(SC.OddballMorton.menuOptions(mg,player)),
    "Buster sees an actually worn bunny costume")
check(SC.OddballMorton.action(mg,"roast",player)
    and string.find(morton.lines[#morton.lines],"costume",1,true),
    "costume roast responds to visible clothes")
SC.Factions.list=oldList

player.x,player.y=30,30
local mien,wr=actor("mien",30,30,0)
local wg=group("mien_ward",mien,wr)
check(SC.OddballMien.onSpawn(wg,mien),"saucepan prepared")
check(not SC.OddballMien.action(wg,"start_brew",player)
    and wg.oddball.stage=="hunting_ingredients",
    "no invented beer without ingredients")
for kind,count in pairs({["Base.Hops"]=4,["Base.Yeast"]=2,
    ["Base.Sugar"]=2,["Base.Bucket"]=1}) do
    for _=1,count do add(player.inv,kind) end
end
local before=#player.inv.items
mien.inv.rejectType="Base.Yeast"
check(not SC.OddballExchange.take(player,mien,
    {["Base.Hops"]=4,["Base.Yeast"]=2}),
    "rejected ingredient aborts exact transfer")
check(#player.inv.items==before and wg.oddball.stage=="hunting_ingredients",
    "partial transfer rolls back without item loss")
mien.inv.rejectType=nil
hour=100
check(SC.OddballMien.action(wg,"start_brew",player),"exact brew supplies")
hour=267
SC.OddballMien.pulse(wg,player,now)
check(wg.oddball.stage=="fermenting","seven days not yet elapsed")
hour=268
SC.OddballMien.pulse(wg,player,now)
check(wg.oddball.stage=="batch_ready","saved timer completed")
check(SC.OddballMien.action(wg,"claim_batch",player),"six actual beers")
check(wg.oddball.stage=="batch_claimed" and SC.OddballMien.canRecruit(wg),
    "no repeat batch and recruitment unlocked")

player.x,player.y=40,40
local grinder,br=actor("grinder",40,40,0)
local bg=group("grinder_berg",grinder,br)
br.identity.keepsakeType="Base.Screwdriver"
check(SC.OddballGrinder.onSpawn(bg,grinder),"crowbar and vodka")
check(grinder.hand and grinder.hand.kind=="Base.Crowbar","crowbar equipped")
local possessions=SC.PersonalItems.ensure(grinder,nil)
check(possessions and possessions.keepsake
    and possessions.keepsake.itemType=="Base.Screwdriver",
    "identity-selectable screwdriver enters personal-item lifecycle")
check(SC.PersonalItems.find(grinder,possessions.keepsake.key)~=nil,
    "actual screwdriver marked as protected keepsake")
for kind,count in pairs({["Base.ElectronicsScrap"]=10,
    ["Base.ElectricWire"]=2,["Base.Battery"]=4}) do
    for _=1,count do add(player.inv,kind) end
end
check(SC.OddballGrinder.action(bg,"generator_lesson",player),
    "exact components exchanged")
check(bg.oddball.lessonGiven and SC.OddballGrinder.canRecruit(bg),
    "one-time real generator manual and recruitment")
check(not SC.OddballGrinder.action(bg,"generator_lesson",player),
    "no duplicate magazine")
SC_TEST_REPORT="Final four PASS: "..checks.." checks"
