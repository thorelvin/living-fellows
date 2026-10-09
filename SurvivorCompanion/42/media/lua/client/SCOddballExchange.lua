-- SPDX-License-Identifier: MIT
-- Shared exact, reversible item transfer for authored encounter contracts.
local SC = SurvivorCompanion
SC.OddballExchange = SC.OddballExchange or {}
local X = SC.OddballExchange
local function U() return SC.GameplayUtil end
function X.select(actor, requirements)
    local inv=actor and U().inventory(actor)
    if not inv then return nil end
    local found={}
    for kind in pairs(requirements) do found[kind]={} end
    for _,item in ipairs(U().inventoryItemsDeep(inv,360,12)) do
        local kind=U().itemType(item)
        local list=found[kind]
        if list and #list<requirements[kind] then list[#list+1]=item end
    end
    local selected={}
    for kind,count in pairs(requirements) do
        if #found[kind]<count then return nil end
        for _,item in ipairs(found[kind]) do
            selected[#selected+1]=item
        end
    end
    return selected
end
function X.take(player,recipient,requirements)
    local selected=X.select(player,requirements)
    local destination=recipient and U().inventory(recipient)
    if not selected or not destination then return false,"materials_missing" end
    local moved={}
    for _,item in ipairs(selected) do
        local source=select(1,U().call(item,"getContainer"))
        if not source or not U().transferItemVerified(source,destination,item) then
            for index=#moved,1,-1 do
                local entry=moved[index]
                U().transferItemVerified(destination,entry.source,entry.item)
            end
            return false,"materials_transfer_failed"
        end
        moved[#moved+1]={source=source,item=item}
    end
    return true,moved
end
function X.returnMoved(recipient,moved)
    local inventory=recipient and U().inventory(recipient)
    if not inventory then return false end
    local okay=true
    for index=#moved,1,-1 do
        local entry=moved[index]
        if not U().transferItemVerified(inventory,entry.source,entry.item) then
            okay=false end
    end
    return okay
end
return X
