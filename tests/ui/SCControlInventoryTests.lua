-- SPDX-License-Identifier: MIT
-- Material checks must find exact owned items beyond the display survey budget.
local SC,U=SurvivorCompanion,SurvivorCompanion.ControlUtil
local checks=0
local function check(value,message)
    checks=checks+1
    assert(value,"control inventory "..checks..": "..message)
end
local function container()
    local c={items={}}
    function c:getItems() return self.items end
    function c:contains(item)
        for _,candidate in ipairs(self.items) do if candidate==item then return true end end
        return false
    end
    function c:AddItem(item) self.items[#self.items+1]=item item.container=self end
    function c:Remove(item)
        if self.refuse==item then return end
        for i,candidate in ipairs(self.items) do
            if candidate==item then table.remove(self.items,i) item.container=nil return end
        end
    end
    function c:getContainingItem() return self.owner end
    function c:getSomeTypeRecurse(kind,count)
        self.queries=(self.queries or 0)+1
        local result={}
        local function scan(current)
            for _,item in ipairs(current.items) do
                if #result>=count then return end
                if item.fullType==kind then result[#result+1]=item end
                if item.inventory then scan(item.inventory) end
            end
        end
        scan(self)
        return {size=function() return #result end,get=function(_,index) return result[index+1] end}
    end
    return c
end
local function item(kind)
    local value={fullType=kind}
    function value:getFullType() return self.fullType end
    function value:getContainer() return self.container end
    function value:getInventory() return self.inventory end
    return value
end
SC.GameplayUtil={call=function(object,method,...)
    if object and type(object[method])=="function" then return object[method](object,...),true end
    return nil,false
end,containerContainsIdentity=function(c,value) return c and c:contains(value) end}
local inv=container()
local actor={getInventory=function() return inv end}
for _=1,2100 do inv:AddItem(item("Base.Nails")) end
local screwdriver=item("Base.Screwdriver") inv:AddItem(screwdriver)
local wire=item("Base.ElectricWire") inv:AddItem(wire)
local bag=item("Base.Bag_Schoolbag") bag.inventory=container() bag.inventory.owner=bag inv:AddItem(bag)
local scrap={}
for i=1,4 do scrap[i]=item("Base.ElectronicsScrap") bag.inventory:AddItem(scrap[i]) end
check(U.owns(actor,scrap[4]),"ownership is independent of the 2,048-item menu survey")
check(U.hasTool(actor,"Base.Screwdriver"),"tools near the end of a crowded inventory remain usable")
local chosen,reason=U.parts(actor,{["Base.ElectricWire"]=1,["Base.ElectronicsScrap"]=4})
check(chosen and #chosen==5,"all four scraps inside a late bag satisfy the exact backup upgrade: "..tostring(reason))
check(inv.queries==3,"material and tool lookup use quantity-limited native queries")
local okay,receipt=U.consume(actor,{["Base.ElectricWire"]=1,["Base.ElectronicsScrap"]=4})
check(okay and #receipt==5 and not inv:contains(wire) and #bag.inventory.items==0,"consume transfers only the required identities")
U.refund(receipt)
check(inv:contains(wire) and #bag.inventory.items==4 and U.owns(actor,scrap[4]),"refund restores those same identities to their original bags")
bag.inventory.refuse=scrap[3]
check(not U.consume(actor,{["Base.ElectronicsScrap"]=4}) and #bag.inventory.items==4,"failed removal rolls back earlier parts without duplicating them")
bag.inventory.refuse=nil
local world=container() inv:Remove(bag) world:AddItem(bag)
check(not U.owns(actor,scrap[1]),"a bag placed outside the actor no longer grants ownership")
local missing,message=U.parts(actor,{["Base.ElectronicsScrap"]=4})
check(not missing and message:find("x4",1,true),"four scraps in a world container do not satisfy personal materials")
-- A stale native result must not bypass exact ownership checks.
inv.getSomeTypeRecurse=function() return {scrap[1],scrap[1],scrap[2],scrap[3]} end
check(not U.parts(actor,{["Base.ElectronicsScrap"]=4}),"foreign or duplicate native candidates cannot be consumed")
-- A corrupt containment cycle cannot hang the transaction.
local cycle=item("Base.Bag_Schoolbag") cycle.inventory=container() cycle.inventory.owner=cycle cycle.inventory:AddItem(cycle)
check(not U.owns(actor,cycle),"containment cycles do not establish personal ownership")
print("PASS control inventory checks="..checks)
