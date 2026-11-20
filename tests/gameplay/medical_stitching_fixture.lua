-- SPDX-License-Identifier: MIT
-- The fixture models only effects established by the native Phase 0 probe.
local SC=SurvivorCompanion
local F={serial=400000}
local Base=SC.TestMedicalProcedures
Perks.Doctor=Perks.Doctor or 'Doctor'
function F.part(options)
    local part=Base.part(options or {})
    function part:isGetStitchXp() return self.getStitchXp==true end
    function part:setStitched(enabled)
        self.stitchCalls=(self.stitchCalls or 0)+1
        if self.rejectStitch then return end
        self.stitchWhileCovered=self.isBandaged==true
        self.stitchFlag=enabled
        if enabled then self.deep,self.deepTime,self.isBleeding=false,0,false
        else self.stitchTime,self.scratchTime,self.isScratched=0,4,true end
        if self.throwAfterStitch then error('exception after irreversible stitch') end
    end
    function part:setStitchTime(value)
        self.stitchTimeCalls=(self.stitchTimeCalls or 0)+1
        if not self.rejectStitchTime then self.stitchTime=value end
    end
    return part
end
function F.item(kind,options)
    F.serial=F.serial+1
    local item=Base.item(kind,options)
    item.nativeId=F.serial
    function item:getID() return self.nativeId end
    return item
end
function F.patient(options,kind)
    options=options or {}
    if options.deepTime==nil then options.deepTime=20 end
    if options.isBandaged==nil then options.isBandaged=true end
    if options.bandageType==nil then options.bandageType='Base.Bandage' end
    if options.bandageLife==nil then options.bandageLife=12 end
    local part=F.part(options)
    local fresh=F.item('Base.Bandage')
    local consume=F.item(kind=='suture' and 'Base.SutureNeedle' or 'Base.Thread',
        {drainable=kind~='suture',uses=kind=='suture' and 1 or 20})
    local needle=kind~='suture' and F.item('Base.Needle') or nil
    local items={fresh,consume};if needle then items[#items+1]=needle end
    return Base.actor({part},items),part,fresh,consume,needle
end
SC.TestMedicalStitching=F
