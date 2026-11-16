-- SPDX-License-Identifier: MIT
-- Three real registered tool destinations, exact item capacity and identity.
local SC=SurvivorCompanion
local f=assert(SC.TestFixture)
local checks=0
local function check(value,message)
    checks=checks+1;assert(value,"tool storage " .. checks .. ": " .. message)
end
SC.NativeActions={stopDirect=function() return true end,
    visualStatus=function() return "completed" end,clearVisual=function() return true end}
SC.Navigation={cancel=function() return true end,
    requestAny=function(a,targets)
        a.square=SC.GameplayUtil.squareOf(targets[1])
        return a.square~=nil,"moving"
    end}
SC.GameplayUtil.move=function() return true end
SC.GameplayUtil.directInteractionAccess=function(a,object)
    if a.square==object:getSquare() then return true end
    return false,{object:getSquare()},"not_at_storage"
end
local serial=0
local function fixture(filled)
    serial=serial+1
    SC.BaseWork.reset();SC.BaseLife.reset()
    local centre=f.makeSquare(5,5,0)
    check(SC.BaseLife.create(centre,"Tool overflow test"),"camp created")
    local a=f.actor("sc-overflow-" .. serial,5,5)
    local rows,containers={},{}
    for index=1,3 do
        local sq=f.makeSquare(5+index,5,0)
        local contents=index<=filled and {f.item("Base.Stone","Item",{weight=3})} or {}
        local container,object=f.containerObject(sq,contents)
        container.capacity=3
        function object:getObjectIndex()
            for n,o in ipairs(self.square.objects) do if o==self then return n-1 end end
            return -1
        end
        local ok,row=SC.BaseLife.registerStorage(object,"tools")
        check(ok and row~=nil,"tool storage " .. index .. " registered")
        rows[index],containers[index]=row,container
    end
    local tool=f.item("Base.Hammer","Tool",{weight=1.5,tags={Hammer=true}})
    a:getInventory():AddItem(tool)
    return a,rows,containers,tool
end
local function finish(a,rows,containers,tool,state)
    local ok,reason
    for _=1,10 do
        f.clock=f.clock+1000
        ok,reason=SC.BaseWork.returnToStorage(a,state or {},rows[1],containers[1],tool)
        if reason=="base_supply_returned" or ok~=true then break end
    end
    return ok,reason
end
do
    local a,rows,containers,tool=fixture(0)
    local ok,why=finish(a,rows,containers,tool,{})
    check(ok and why=="base_supply_returned" and tool:getContainer()==containers[1],
        "an original tool shelf with space is still preferred: " .. tostring(why))
end
for filled=1,2 do
    local a,rows,containers,tool=fixture(filled)
    local ok,why=finish(a,rows,containers,tool,{})
    check(ok and why=="base_supply_returned" and tool:getContainer()==containers[filled+1],
        "full tool shelves fall through to shelf " .. (filled+1) .. ": " .. tostring(why))
    check(not a:getInventory():contains(tool) and containers[filled+1]:contains(tool),
        "the exact borrowed tool has one verified new owner")
end
do
    local a,rows,containers,tool=fixture(1)
    rows[2].deposits=false
    local ok,why=finish(a,rows,containers,tool,{})
    check(ok and tool:getContainer()==containers[3] and not containers[2]:contains(tool),
        "a deposit-disabled secondary shelf is skipped: " .. tostring(why))
end
do
    local a,rows,containers,tool=fixture(3)
    local state={}
    local ok,why=finish(a,rows,containers,tool,state)
    check(not ok and why=="destination_full" and tool:getContainer()==a:getInventory(),
        "all-full storage retains the exact tool with its carrier")
    containers[3]:Remove(containers[3].items[1])
    ok,why=finish(a,rows,containers,tool,state)
    check(ok and tool:getContainer()==containers[3],"freeing overflow space unblocks the same return: " .. tostring(why))
end
do
    local a,rows,containers,tool=fixture(1)
    local destinations,category=SC.BaseWork.floorDestinations(a,tool)
    check(category=="tools" and #destinations==2
        and destinations[1].destination==rows[2] and destinations[2].destination==rows[3],
        "ordinary sorting already sees both secondary tool shelves")
end
do
    local a,rows,containers,tool=fixture(1)
    containers[2]:AddItem(f.item("Base.Stone","Item",{weight=1.5}))
    local ok,why=finish(a,rows,containers,tool,{})
    check(ok and tool:getContainer()==containers[2] and containers[2]:getFreeCapacity(a)==0,
        "an exact-fit secondary accepts the full tool without exceeding capacity: " .. tostring(why))
    local moves=a:getInventory().removeCalls
    ok,why=finish(a,rows,containers,tool,{})
    check(ok and why=="base_supply_returned" and a:getInventory().removeCalls==moves,
        "replaying completion recognises the exact tool already stored in overflow")
end
do
    local a,rows,containers,tool=fixture(1)
    local phase="active"
    SC.NativeActions.visualStatus=function() return phase end
    local cancelled=0
    SC.NativeActions.cancelVisual=function() cancelled=cancelled+1 return true end
    local state={}
    for _=1,4 do
        SC.BaseWork.returnToStorage(a,state,rows[1],containers[1],tool)
        if state.visualAt then break end
    end
    check(state.visualAt~=nil and tool:getContainer()==a:getInventory(),
        "overflow return waits under its native loot pose before commit")
    containers[2]:AddItem(f.item("Base.Stone","Item",{weight=3}))
    phase="completed"
    local ok,why=finish(a,rows,containers,tool,state)
    check(ok and tool:getContainer()==containers[3] and cancelled==1,
        "a secondary filling during Loot cancels that pose and retargets the third: " .. tostring(why))
end
do
    local a,rows,containers,tool=fixture(0)
    rows[1].deposits=false
    local ok,why=finish(a,rows,containers,tool,{})
    check(ok and tool:getContainer()==containers[2],
        "a tool return honours deposit permission even on its original shelf: " .. tostring(why))
end
do
    local a,rows,containers,tool=fixture(1)
    local resolve=SC.BaseLife.resolveContainer
    SC.BaseLife.resolveContainer=function(row)
        if row==rows[2] then return nil end
        return resolve(row)
    end
    local ok,why=finish(a,rows,containers,tool,{})
    SC.BaseLife.resolveContainer=resolve
    check(ok and tool:getContainer()==containers[3],
        "an unloaded secondary shelf does not hide a loaded third shelf: " .. tostring(why))
end
SC_TEST_REPORT="TOOL_STORAGE_OVERFLOW_PASS checks=" .. checks
