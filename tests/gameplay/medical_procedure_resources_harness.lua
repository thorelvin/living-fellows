-- SPDX-License-Identifier: MIT
-- Exact native-resource outcomes and secondary-effect failures through treat().
local SC=LivingFellows
local M,F,U=SC.Medical,SC.TestMedicalProcedures,SC.GameplayUtil
local checks=0
local function check(value,reason) checks=checks+1;assert(value,'procedure resources '..checks..': '..reason) end
local native,supervisor,move,stop,oldXp=SC.NativeActions,SC.ActionSupervisor,U.move,U.stop,addXp
SC.NativeActions,SC.ActionSupervisor=nil,nil
U.move=function() return true end;U.stop=function() return true end
local globalXpCalls=0
addXp=function() globalXpCalls=globalXpCalls+1 end
local function xpRequest(actor,amount,label)
    local args=actor.medicalXpCalls[1]
    check(#actor.medicalXpCalls==1 and args and args.count==6 and args[1]==Perks.Doctor and args[2]==amount
        and args[3]==true and args[4]==true and args[5]==false and args[6]==false,
        label..' requests exact native base XP with vanilla multiplier flags')
end
local function covered(kind)
    local options={isBandaged=true,bandageType='Base.Bandage',bandageLife=10}
    if kind=='burn' then options.burn,options.needBurnWash=10,true else options.bullet=true end
    return F.part(options)
end
local function released(actor,label)
    check(M.peek(actor)==nil and M.treatmentHolder(actor)==nil,label..' releases helper and patient claim')
end
local function terminal(actor,label)
    local pending=M.pendingCare(actor)
    check(pending and pending.quarantined and pending.terminalQuarantine and pending.active==false,
        label..' retains inactive forensic proof without immobilizing the patient')
    released(actor,label)
end
local function retired(actor,result)
    local recent=SC.MedicalMaintenance.recent()
    check(M.pendingCare(actor)==nil and recent[#recent].result==result,
        'verified absent bullet clears its hold and preserves the secondary result '..result)
    released(actor,result)
end

-- A replacement is appended at the end of its actual source container. The
-- ordinary discovery prefix is not a complete post-effect inventory receipt.
local fresh,cleaner=F.item('Base.Bandage'),F.item('Base.RippedSheets')
local p=covered('burn')
local actor=F.actor({p},{fresh,cleaner})
for index=1,400 do actor.inventory:AddItem(SC.TestFixture.item('Base.Stone','Item')) end
local okay,why=M.treat(actor,actor)
check(okay and why=='burn_cleaned','native burn output past the400-item discovery prefix verifies normally')
check(not p.needBurnWash and p.isBandaged and p.burnCleanCalls==1,'large inventory does not repeat burn cleanup')
check(not actor.inventory:contains(fresh) and not actor.inventory:contains(cleaner)
    and F.count(actor.inventory,'Base.RippedSheetsDirty')==1,'large inventory consumes the exact two resources and retains one native output')
check(cleaner.useCalls==1 and M.pendingCare(actor)==nil,'source-complete verification settles its debit once')
released(actor,'large inventory')
xpRequest(actor,10,'burn cleaning')

-- The injury effect is irreversible; a failed pain setter must redress safely
-- and report uncertainty rather than calling the same operation again.
fresh=F.item('Base.Bandage');local tool=F.item('Base.Tweezers')
p=covered('bullet')
function p:setAdditionalPain(value) self.painCalls=(self.painCalls or 0)+1 end
actor=F.actor({p},{fresh,tool})
okay,why=M.treat(actor,actor)
check(okay and why=='medical_procedure_unverified','refused native pain is reported as an unverified secondary effect')
check(not p.bullet and p.bulletCalls==1 and p:getAdditionalPain()==0 and p.isBandaged,
    'pain failure preserves verified removal and completes safe redress')
check(not actor.inventory:contains(fresh) and actor.inventory:contains(tool),'pain failure spends only its exact fresh dressing')
retired(actor,why)
xpRequest(actor,20,'bullet removal')
local requests=#actor.medicalXpCalls
for index=1,4 do M.treat(actor,actor) end
check(p.bulletCalls==1 and p.painCalls==1 and #actor.medicalXpCalls==requests,'pain failure never replays injury effect, pain request or XP')

-- Native partial effects can leave both original and replacement. Presence of
-- either alone is not permission to spend again on the following decision.
fresh,cleaner=F.item('Base.Bandage'),F.item('Base.RippedSheets')
function cleaner:UseAndSync()
    self.useCalls=(self.useCalls or 0)+1
    self.container:AddItem('Base.RippedSheetsDirty')
end
p=covered('burn');actor=F.actor({p},{fresh,cleaner})
okay,why=M.treat(actor,actor)
check(okay and why=='medical_consumption_uncertain','original-plus-output partial burn is quarantined')
check(not p.needBurnWash and p.isBandaged and not actor.inventory:contains(fresh)
    and actor.inventory:contains(cleaner),'partial consumption still redresses and preserves exact surviving input')
check(cleaner.useCalls==1 and F.count(actor.inventory,'Base.RippedSheetsDirty')==1,'partial native effect creates one retained actual output')
terminal(actor,'partial burn')
requests=#actor.medicalXpCalls
for index=1,4 do M.treat(actor,actor) end
check(cleaner.useCalls==1 and p.burnCleanCalls==1 and #actor.medicalXpCalls==requests
    and F.count(actor.inventory,'Base.RippedSheetsDirty')==1,'partial burn never replays debit, body effect or XP')

-- A modded AddItem may mutate successfully then return nil or throw. Observe
-- the unique actual identity rather than creating the previous covering twice.
for _,mode in ipairs({'nil','throw'}) do
    fresh,tool=F.item('Base.Bandage'),F.item('Base.Tweezers')
    p=covered('bullet');actor=F.actor({p},{fresh,tool})
    local inventory,add=actor.inventory,actor.inventory.AddItem
    local returns=0
    inventory.AddItem=function(self,item)
        local result=add(self,item)
        if item=='Base.Bandage' then
            returns=returns+1
            if mode=='throw' then error('injected AddItem exception after returned covering exists') end
            return nil
        end
        return result
    end
    okay,why=M.treat(actor,actor)
    check(okay and why=='bullet_removed','unique observed old-cover return survives AddItem '..mode)
    check(returns==1 and F.count(inventory,'Base.Bandage')==1 and not inventory:contains(fresh),
        'AddItem '..mode..' returns one actual old covering and consumes exact fresh supply')
    check(not p.bullet and p.isBandaged and p.bulletCalls==1 and M.pendingCare(actor)==nil,
        'AddItem '..mode..' settles verified surgery and redress')
    released(actor,'AddItem '..mode)
    for index=1,3 do M.treat(actor,actor) end
    check(returns==1 and F.count(inventory,'Base.Bandage')==1,'AddItem '..mode..' return cannot be replayed')
end

fresh,tool=F.item('Base.Bandage'),F.item('Base.Tweezers')
p=covered('bullet');actor=F.actor({p},{fresh,tool})
local inventory,add=actor.inventory,actor.inventory.AddItem
local attempts=0
inventory.AddItem=function(self,item)
    local result=add(self,item)
    if item=='Base.Bandage' then attempts=attempts+1;add(self,item);return nil end
    return result
end
okay,why=M.treat(actor,actor)
check(okay and why=='medical_return_uncertain' and p.isBandaged and not p.bullet,
    'ambiguous native returns report uncertainty after safe redress')
retired(actor,why)
for index=1,4 do M.treat(actor,actor) end
check(attempts==1 and F.count(inventory,'Base.Bandage')==2 and p.bulletCalls==1,
    'ambiguous return preserves observed objects without adding any further copy')

fresh,tool=F.item('Base.Bandage'),F.item('Base.Tweezers')
p=F.part({glass=true,scratchTime=4,isBandaged=true,bandageType='Base.Bandage',bandageLife=10})
actor=F.actor({p},{fresh,tool})
okay,why=M.treat(actor,actor)
check(okay and why=='glass_removed' and p.glassCalls==1,'native glass removal completes before its XP request '..tostring(okay)..'/'..tostring(why)..'/'..tostring(p.glassCalls))
xpRequest(actor,15,'glass removal')
for index=1,3 do M.treat(actor,actor) end
check(#actor.medicalXpCalls==1,'completed glass removal does not replay its native XP request')
check(globalXpCalls==0,'shared clinical XP bypasses the NPC-gated global wrapper without changing base values')

SC.NativeActions,SC.ActionSupervisor,U.move,U.stop,addXp=native,supervisor,move,stop,oldXp
print('Medical procedure resource checks='..checks)
