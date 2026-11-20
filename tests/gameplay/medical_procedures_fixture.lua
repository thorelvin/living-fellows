-- SPDX-License-Identifier: MIT
-- Clinical fixture only. Native effect facts are verified in the PZO probe.
local SC,F=SurvivorCompanion,SurvivorCompanion.TestFixture
local Fixture={serial=0}
Perks.Doctor=Perks.Doctor or 'Doctor'
function Fixture.part(options)
    local p=F.bodyPart(options or {})
    for method,field in pairs({getBiteTime="biteTime",getScratchTime="scratchTime",getCutTime="cutTime",
        getDeepWoundTime="deepTime",getStitchTime="stitchTime",getAlcoholLevel="alcoholLevel",
        getWoundInfectionLevel="infectionLevel",getLastTimeBurnWash="lastBurnWash"}) do
        local name=field;p[method]=function(self) return self[name] or 0 end
    end
    function p:stitched() return self.stitchFlag==true end
    function p:isSplint() return self.splintFlag==true end
    function p:getSplintFactor() return self.splintFactor or 0 end
    function p:getSplintItem() return self.splintItem end
    function p:setSplint(enabled,factor) self.splintFlag=enabled;self.splintFactor=factor end
    function p:isNeedBurnWash() return self.needBurnWash==true end
    function p:setNeedBurnWash(value)
        self.burnCleanCalls=(self.burnCleanCalls or 0)+1;self.needBurnWash=value
        if not value then self.lastBurnWash=self.burn or 0 end
    end
    function p:getAdditionalPain() return self.additionalPain or 0 end
    function p:setAdditionalPain(value) self.additionalPain=value end
    function p:setAlcoholLevel(value) self.alcoholCalls=(self.alcoholCalls or 0)+1;self.alcoholLevel=value end
    function p:setInfectedWound(value) self.infectedWound=value end
    function p:isGetStitchXp() return false end
    function p:setBandaged(enabled,life,alcoholic,kind)
        self.isBandaged,self.bandageLife,self.bandageAlcoholic,self.bandageType=enabled,life,alcoholic,kind
        self.stitchFlag=not enabled and self:getStitchTime()>0
        self.deep=not enabled and self:getDeepWoundTime()>0
        self.isScratched=not enabled and self:getScratchTime()>0
        self.cut=not enabled and self:getCutTime()>0
    end
    function p:setHaveBullet(value,doctor)
        self.bulletCalls=(self.bulletCalls or 0)+1
        if self.rejectBullet then return end
        self.bullet=value
        if not value then self.deep,self.deepTime,self.isBleeding=true,20-(doctor or 0),true end
        if self.throwAfterBullet then error('native exception after bullet removal') end
    end
    function p:setHaveGlass(value)
        self.glassCalls=(self.glassCalls or 0)+1
        if self.rejectGlass then return end
        self.glass=value
        if self.throwAfterGlass then error('native exception after glass removal') end
    end
    return p
end
function Fixture.item(kind,options)
    local item=F.item(kind,'Medical',options)
    function item:isCanBandage() return string.find(self.itemType,'Bandage',1,true)~=nil or self.itemType=='Base.RippedSheets' end
    function item:getBandagePower()
        if self.bandagePower~=nil then return self.bandagePower end
        return self:isCanBandage() and not self:isDirty() and (self.itemType=='Base.RippedSheets' and 2 or 4) or 0
    end
    function item:IsDrainable() return self.drainable==true end
    function item:getCurrentUses() return self.uses or 0 end
    function item:getUseDelta() return self.useDelta or 0.2 end
    function item:getAlcoholPower() return self.alcoholPower or 0 end
    function item:UseAndSync()
        self.useCalls=(self.useCalls or 0)+1
        if self.rejectUse then return false end
        local source=self.container
        if self:isCanBandage() then
            source:Remove(self);source:AddItem(self.itemType=='Base.RippedSheets' and 'Base.RippedSheetsDirty' or 'Base.BandageDirty')
        else
            self.uses=self.uses-1;if self.uses<=0 then source:Remove(self) end
        end
        if self.throwAfterUse then error('native exception after consumption') end
    end
    return item
end
function Fixture.actor(parts,items)
    Fixture.serial=Fixture.serial+1
    local actor=F.actor('procedure-'..Fixture.serial,20+(Fixture.serial%15),25,
        {body=F.bodyDamage(100,parts),inventory=F.inventory(items or {})})
    actor.medicalXpCalls={}
    local experience={}
    function experience:AddXP(...)
        local args={...};args.count=select('#',...)
        actor.medicalXpCalls[#actor.medicalXpCalls+1]=args
        actor.medicalXpRequested=args[2]
        if actor.throwAfterXp then error('exception after native XP request') end
    end
    function actor:getXp() return experience end
    SC.GameplayUtil.actorState(actor).snapshot={valid=true,time=SC.GameplayUtil.nowMs(),immediateCount=0,closeThreatCount=0,threatCount=0}
    return actor
end
function Fixture.count(container,kind)
    local result=0
    for _,item in ipairs(container.items) do if item:getFullType()==kind then result=result+1 end end
    return result
end
SC.TestMedicalProcedures=Fixture
