-- SPDX-License-Identifier: MIT
-- Exact, temporary outfits for bathroom routines. Effects remain stock actions.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.HygieneClothing = SC.HygieneClothing or {}
local Clothing = SC.HygieneClothing
local claims = setmetatable({}, {__mode="k"})
local function U() return SC.GameplayUtil end
local function owned(actor, item)
    local source = select(1,U().call(item,"getContainer"))
    local root = U().inventory(actor)
    return (source==root or select(1,U().call(item,"getOutermostContainer"))==root)
        and U().containerContainsIdentity(source,item)==true
end

local lowerLocations = {
    pants=true, pantsextra=true, shorts=true, skirt=true, longskirt=true,
    dress=true, longdress=true, underwearbottom=true, underwear=true,
    underwearextra1=true, underwearextra2=true, torso1legs1=true,
    fullsuit=true, fullsuithead=true, fullsuitheadscba=true,
    boilersuit=true, bodycostume=true, bathrobe=true, fullrobe=true,
}
function Clothing.lowerBody(item, location)
    local key=string.lower(tostring(location or select(1,U().call(item,"getBodyLocation")) or ""))
        :match("([^:]+)$")
    return lowerLocations[key and key:gsub("_","") or ""]==true
end

local function release(actor, owner)
    owner.hygieneWardrobe=nil
    if claims[actor]==owner then claims[actor]=nil end
end

local function step(actor, owner, restoring, immediate)
    local receipt=owner.hygieneWardrobe
    if not receipt then return true end
    if receipt.actor~=actor or claims[actor]~=owner then return false,"hygiene_clothing_wrong_actor" end
    if U().isDead(actor) then release(actor,owner); return true end
    local native=SC.NativeActions
    if not native or not native.startClothing or not native.restoreClothingNow then
        return false,"native_clothing_unavailable"
    end
    local token=receipt.token
    if token then
        if immediate or restoring and receipt.phase~="dressing" then
            local stopped,why=native.cancelVisualOwned(actor,token,"hygiene_restoring")
            if not stopped then return false,why end
        else
            if native.visualToken(actor,"wear_clothing")~=token then return false,"hygiene_clothing_ownership_lost" end
            local status=native.visualStatus(actor,"wear_clothing")
            if status=="active" then
                if U().nowMs()-receipt.startedAt>30000 then return false,"hygiene_clothing_timeout" end
                return nil,restoring and "getting_dressed" or "removing_lower_clothing"
            end
            local row=receipt.rows[receipt.index]
            local before=not restoring and {
                Primary=select(1,U().call(actor,"getPrimaryHandItem")),
                Secondary=select(1,U().call(actor,"getSecondaryHandItem")),
            }
            if status~="completed" or not native.commitClothingVisual(actor,token,row.item,not restoring) then
                return false,"hygiene_clothing_interrupted"
            end
            if before then for _,side in ipairs({"Primary","Secondary"}) do
                if before[side]==receipt.handsAfter[side] then
                    receipt.handsAfter[side]=select(1,U().call(actor,"get"..side.."HandItem"))
                end
            end end
            local cancelled,why=native.cancelVisualOwned(actor,token,"hygiene_clothing_completed")
            if not cancelled then return false,why end
        end
        receipt.token=nil
    end
    if restoring and (receipt.phase~="dressing" or immediate) then
        receipt.phase,receipt.index="dressing",1
    end
    while receipt.index<=#receipt.rows do
        local row=receipt.rows[receipt.index]
        local equipped=select(1,U().call(actor,"isEquippedClothing",row.item))==true
        local slot=select(1,U().call(actor,"getWornItem",row.location))
        local skip=restoring and (row.keepWorn or select(1,U().call(row.item,"isBroken"))==true
            or slot==row.item or not owned(actor,row.item) or equipped or slot~=nil)
            or not restoring and (not equipped or row.keepWorn)
        if restoring and skip and slot~=row.item and not row.keepWorn then
            owner.fact=owner.fact or {}; owner.fact.outfitChanged=true
        end
        if not skip then
            if not owned(actor,row.item) then return false,"hygiene_clothing_not_owned" end
            if restoring then
                local source=select(1,U().call(row.item,"getContainer"))
                if source~=U().inventory(actor) and U().transferItemVerified(source,U().inventory(actor),row.item)~=true then
                    return false,"hygiene_clothing_transfer_failed"
                end
            end
            local function owns() return claims[actor]==owner and owner.hygieneWardrobe==receipt
                and receipt.owns() and not U().isDead(actor) end
            if immediate then
                if not native.restoreClothingNow(actor,row.item,row.location,owns) then return false,"hygiene_clothing_restore_pending" end
            else
                local started,why=native.startClothing(actor,row.item,not restoring,function()
                    return owns() and owner.cancelRequestedReason==nil and receipt.valid()
                end,restoring and row.location or nil)
                if not started then return false,why end
                receipt.token=native.visualToken(actor,"wear_clothing")
                receipt.startedAt=U().nowMs()
                return nil,restoring and "getting_dressed" or "removing_lower_clothing"
            end
        end
        if restoring and select(1,U().call(actor,"getWornItem",row.location))==row.item and row.wasActivated then
            U().call(row.item,"setActivated",true)
            if type(syncItemActivated)=="function" then syncItemActivated(actor,row.item) end
        end
        receipt.index=receipt.index+1
    end
    if restoring then
        for _,side in ipairs({"Primary","Secondary"}) do
            local current=select(1,U().call(actor,"get"..side.."HandItem"))
            if current==receipt.handsAfter[side] and receipt.hands[side] and owned(actor,receipt.hands[side]) then
                U().call(actor,"set"..side.."HandItem",receipt.hands[side])
            end
        end
        release(actor,owner)
    else receipt.phase="removed" end
    U().call(actor,"resetModelNextFrame")
    return true
end

function Clothing.undress(actor, owner, options)
    if not owner.hygieneWardrobe then
        options=options or {}
        if claims[actor] and claims[actor]~=owner then return false,"hygiene_outfit_already_owned" end
        local worn=select(1,U().call(actor,"getWornItems"))
        local size=worn and select(1,U().call(worn,"size")) or 0
        if not tonumber(size) or size>64 then return false,"hygiene_outfit_unavailable" end
        local rows={}
        for index=0,size-1 do
            local entry=select(1,U().call(worn,"get",index))
            local item=select(1,U().call(entry,"getItem"))
            local location=select(1,U().call(entry,"getLocation"))
            if item and location and (not options.filter or options.filter(item,location)) then
                local keepWorn=select(1,U().call(item,"isBroken"))==true
                    or type(isForceDropHeavyItem)=="function" and isForceDropHeavyItem(item)
                if keepWorn and options.requireRemoved then return false,"lower_clothing_cannot_be_removed" end
                rows[#rows+1]={item=item,location=location,keepWorn=keepWorn,
                    wasActivated=select(1,U().call(item,"isActivated"))==true}
            end
        end
        local hands={Primary=select(1,U().call(actor,"getPrimaryHandItem")),Secondary=select(1,U().call(actor,"getSecondaryHandItem"))}
        owner.hygieneWardrobe={actor=actor,rows=rows,index=1,phase="undressing",hands=hands,
            handsAfter={Primary=hands.Primary,Secondary=hands.Secondary},
            owns=options.owns or function() return true end,valid=options.valid or function() return true end}
        claims[actor]=owner
    end
    return step(actor,owner,false,false)
end

function Clothing.restore(actor, owner, immediate)
    return step(actor,owner,true,immediate==true)
end

function Clothing.outfitForSave(actor, owner)
    owner=owner or claims[actor]
    local receipt=owner and owner.hygieneWardrobe
    if not receipt or receipt.actor~=actor or claims[actor]~=owner then return nil end
    local outfit={worn={}}
    for _,row in ipairs(receipt.rows) do
        if select(1,U().call(actor,"getWornItem",row.location))==nil and owned(actor,row.item)
            and select(1,U().call(actor,"isEquippedClothing",row.item))~=true
            and select(1,U().call(row.item,"isBroken"))~=true then
            outfit.worn[#outfit.worn+1]={item=row.item,location=row.location}
        end
    end
    for _,side in ipairs({"Primary","Secondary"}) do
        local item=receipt.hands[side]
        if item and owned(actor,item) and select(1,U().call(actor,"get"..side.."HandItem"))==nil then
            outfit[string.lower(side)]=item
        end
    end
    return outfit
end
return Clothing
