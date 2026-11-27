-- SPDX-License-Identifier: MIT
-- Commands must retain cosmetic attachments without leaking another viewer's skill.
local SC, f = LivingFellows, LivingFellows.TestFixture
local check = f.check
local patient = f.actor("medical-summary-patient", 2, 1, {})
f.registry[patient.id] = patient
local oldDoctor, oldAssess, oldCached = Perks.Doctor, SC.Medical.assess, SC.Medical.assessCached
Perks.Doctor = "Doctor"
local novice = f.actor("medical-summary-novice", 0, 1, {})
local doctor = f.actor("medical-summary-doctor", 0, 1, {})
novice.perks, doctor.perks = { Doctor = 6 }, { Doctor = 7 }
local assessment = {
    health = 100, woundCount = 0, knoxInfected = false, infectionLevel = 0,
    wounds = {
        { name = "Foot_L", index = 0, stitched = true, stitchReady = true, stitchTime = 45 },
        { name = "Hand_L", index = 1, stitched = true, stitchReady = false, stitchTime = 20 },
        { name = "Foot_R", index = 2, splinted = true, boneHealed = true },
        { name = "Hand_R", index = 3, healed = true, bandaged = true, dirtyBandage = true },
        { name = "Torso_Lower", index = 4, bullet = true, glass = true },
    },
}
SC.Medical.assess = function(actor)
    check(actor == patient, "the summary must assess its selected patient")
    return assessment
end
SC.Medical.assessCached = SC.Medical.assess
local noviceSummary = SC.Commands.describe(patient.id, novice)
check(noviceSummary.woundCount == 0 and #noviceSummary.wounds == 5,
    "UI display rows must retain the assessed active-wound count independently")
check(noviceSummary.wounds[1].stitched == true and noviceSummary.wounds[1].stitchReady == nil
        and noviceSummary.wounds[2].stitched == true and noviceSummary.wounds[2].stitchReady == nil,
    "Doctor 6 sees stitches without either readiness qualifier")
local doctorSummary = SC.Commands.describe(patient.id, doctor)
check(doctorSummary.wounds[1].stitchReady == true and doctorSummary.wounds[2].stitchReady == false,
    "Doctor 7 sees both ready and needs-time values, including explicit false")
check(doctorSummary.wounds[3].splinted == true and doctorSummary.wounds[3].boneHealed == true
        and doctorSummary.wounds[4].healed == true and doctorSummary.wounds[4].dirtyBandage == true
        and doctorSummary.wounds[5].bullet == true and doctorSummary.wounds[5].glass == true,
    "the detached medical summary preserves splints, healed dressings and embedded objects")
check(SC.Commands.describe(patient.id, novice).wounds[1].stitchReady == nil,
    "a skilled viewer cannot reveal readiness to the next novice viewer")
check(SC.Commands.describe(patient.id, nil).wounds[1].stitchReady == nil,
    "a viewerless snapshot cannot disclose stitch readiness")
check(assessment.wounds[1].stitchReady == true and assessment.wounds[2].stitchReady == false,
    "viewer filtering must not mutate the cached medical assessment")
doctorSummary.wounds[1].stitched = false
check(assessment.wounds[1].stitched == true,
    "UI mutation cannot change medical facts through a shared wound row")
SC.Medical.assess, SC.Medical.assessCached, Perks.Doctor = oldAssess, oldCached, oldDoctor
print("medical_summary_harness: PASS")
