-- SPDX-License-Identifier: MIT
-- Clinical-only fixture: native timer/eat facts are separately checked in PZO.
local SC=SurvivorCompanion
local F,T=SC.TestMedicalProcedures,SC.TestFixture
local Fixture={serial=97000}
function Fixture.item(kind,options)
    local item=F.item(kind,options)
    Fixture.serial=Fixture.serial+1;item.nativeId=Fixture.serial
    if kind=="Base.Pills" then item.drainable=true;item.useDelta=0.1;item.uses=options and options.uses or 10 end
    if kind=="Base.Antibiotics" then item.uses=item.uses or 1 end
    function item:getID() return self.nativeId end
    function item:getReduceInfectionPower() return self.infectionPower==nil and 50 or self.infectionPower end
    return item
end
function Fixture.register(actor)
    local record={id=actor.id,actor=actor,recruited=true,
        identity={forename="Medicine",surname="Patient",gender="woman",outfit="Generic01"},
        state={personality={}},runtime={}}
    T.registry[actor.id]=record
    SC.Commands.peek(actor)
    return record
end
function Fixture.actor(parts,items)
    local actor=F.actor(parts or {F.part({})},items or {})
    actor.nativePainEffect,actor.nativePainDelta,actor.nativePainReduction,actor.nativeAntibioticPower=0,0,0,0
    actor.moodles={[MoodleType.PAIN]=2}
    function actor:getPainEffect() return self.nativePainEffect end
    function actor:getPainDelta() return self.nativePainDelta end
    function actor:getReduceInfectionPower() return self.nativeAntibioticPower end
    function actor:getBodyDamage() return self.body end
    function actor.body:getPainReduction() return actor.nativePainReduction end
    function actor.body:JustTookPill(item)
        actor.pillCalls=(actor.pillCalls or 0)+1
        if actor.rejectMedicine then return false end
        actor.nativePainEffect=5400;actor.nativePainDelta=actor.nativePainDelta+(actor.intoxicated and 0.15 or 0.45)
        if actor.throwAfterEffect then error("pill effect exception") end
        item:UseAndSync()
        if actor.throwAfterDose then error("pill debit exception") end
    end
    function actor:Eat(item,percentage,utensil)
        self.eatCalls=(self.eatCalls or 0)+1
        assert(percentage==1 and utensil==false,"whole native antibiotic dose")
        if self.rejectMedicine then return false end
        self.nativeAntibioticPower=item:getReduceInfectionPower()
        if self.throwAfterEffect then error("antibiotic effect exception") end
        item:UseAndSync()
        if self.throwAfterDose then error("antibiotic debit exception") end
        return true
    end
    Fixture.register(actor)
    return actor
end
function Fixture.clearPain(actor)
    actor.nativePainEffect,actor.nativePainDelta,actor.nativePainReduction=0,0,0
end
function Fixture.refresh(actor)
    SC.GameplayUtil.actorState(actor).snapshot={valid=true,time=SC.GameplayUtil.nowMs(),immediateCount=0,closeThreatCount=0,threatCount=0}
    SC.Medical.invalidate(actor)
end
SC.TestMedicalMedicines=Fixture
