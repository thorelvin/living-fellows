-- SPDX-License-Identifier: MIT
local T, SC = MEDICAL_CONTEXT_TEST, SurvivorCompanion
local Context = SC.UIContext
local check = T.check
local floor = { getSquare = function() return T.square(11, 11) end }
local worldObjects = { floor }
local menu = T.menu()
local option = T.vanillaOption(menu, worldObjects, T.patient, nil, true)
local originalCallback = option.param1
local getUpWrapper = option.onSelect
check(option.toolTip.description == "Bob needs to be closer.",
    "native stale tooltip refers to the patient's native display name")
Context.fillWorldObjectContextMenu(0, menu, worldObjects, false)
check(#menu.options == 1 and menu.additions == 1 and menu.options[1] == option,
    "floor-only body hit repairs the existing option before an empty-row early return")
check(option.onSelect == getUpWrapper and option.onSelect == menu.onGetUpAndThen and option.target == menu
    and option.param1 == Context.onMedicalCheck and option.param2 == worldObjects
    and option.param3 == T.doctor and option.param4 == T.patient,
    "existing native get-up wrapper retains the actual patient and requester without a clicked row")
check(not option.notAvailable and option.toolTip == nil,
    "nearby registered patient clears stale vanilla distance and consent refusal")
check(SC.UI.instance.selectedId == T.selected.id and option.param4 ~= T.selected,
    "a separately selected Tess never replaces the actual native clicked patient")
check(#T.opened == 0 and SC.MedicalUI.current() == nil and T.getUpAction == nil,
    "menu construction neither opens treatment nor starts an action or stay session")
option.onSelect(option.target, option.param1, option.param2, option.param3, option.param4)
check(T.getUpAction and T.getUpAction.character == T.doctor and #T.opened == 0,
    "selecting the native wrapper queues stand-up before opening companion health")
local opened, reason = T.completeGetUp()
check(opened == true and reason == "health_opened" and #T.opened == 1
    and T.opened[1].patient == T.patient and T.opened[1].doctor == T.doctor,
    "the rebound option opens the actual patient rather than requesting human consent")

T.patient.square.y = 14
Context.ensureCompanionMedicalOption(menu, worldObjects, T.doctor)
check(option.notAvailable and option.toolTip
    and option.toolTip.description == "Move within " .. SC.MedicalUI.RANGE .. " tiles of Jill Kelvin for a medical check."
    and not string.find(option.toolTip.description, "Bob", 1, true)
    and not string.find(option.toolTip.description, "Tess", 1, true),
    "far feedback names the real patient and authoritative range instead of alias or roster selection")
T.patient.square.y = 11
Context.ensureCompanionMedicalOption(menu, worldObjects, T.doctor)
check(not option.notAvailable and option.toolTip == nil and #menu.options == 1,
    "rechecking a now-near patient clears the tooltip without duplicating Medical Check")

local humanMenu = T.menu()
local human = T.vanillaOption(humanMenu, worldObjects, T.human)
local humanTooltip = human.toolTip
Context.ensureCompanionMedicalOption(humanMenu, worldObjects, T.doctor)
check(human.onSelect == originalCallback and human.toolTip == humanTooltip and human.notAvailable,
    "real human-player medical options retain vanilla permission and tooltip behavior")
local humanOpened, humanReason = Context.onMedicalCheck(worldObjects, T.doctor, T.human)
check(humanOpened and humanReason == "vanilla_medical" and #T.originalCalls == 1
    and T.originalCalls[1][2] == T.doctor and T.originalCalls[1][3] == T.human,
    "human callbacks still delegate to the original consent entry point")

local otherRequester = T.actor("second-player", "Second player", 10, 10, false)
local foreignMenu = T.menu()
local foreign = T.vanillaOption(foreignMenu, worldObjects, T.patient, otherRequester, true)
local foreignTooltip = foreign.toolTip
Context.ensureCompanionMedicalOption(foreignMenu, worldObjects, T.doctor)
check(foreign.param3 == otherRequester and foreign.param1 == originalCallback
    and foreign.onSelect == getUpWrapper
    and foreign.toolTip == foreignTooltip,
    "a native option owned by another requester is never silently reassigned")

local unrelatedMenu = T.menu()
local unrelated = T.vanillaOption(unrelatedMenu, worldObjects, T.patient, nil, true)
local unknown = function() error("unrelated callback must not run") end
unrelated.param1 = unknown
local unrelatedTooltip = unrelated.toolTip
Context.ensureCompanionMedicalOption(unrelatedMenu, worldObjects, T.doctor)
check(unrelated.param1 == unknown and unrelated.onSelect == getUpWrapper
    and unrelated.param4 == T.patient and unrelated.toolTip == unrelatedTooltip,
    "a wrapped unknown callback is not hijacked because its label happens to be Medical Check")

local empty = T.menu()
check(Context.ensureCompanionMedicalOption(empty, worldObjects, T.doctor) == nil
    and #empty.options == 0 and empty.additions == 0,
    "missing row and missing native option cannot fabricate a patient from roster selection")

local clicked = T.menu()
local clickedRow = { id = T.patient.id, name = T.patient.name, actor = T.patient }
local explicit = Context.ensureCompanionMedicalOption(clicked, worldObjects, T.doctor, clickedRow)
check(explicit and #clicked.options == 1 and clicked.additions == 1
    and explicit.onSelect == Context.onMedicalCheck and explicit.param2 == T.patient,
    "an explicit clicked companion can still receive its missing native action")
check(Context.ensureCompanionMedicalOption(clicked, worldObjects, T.doctor, clickedRow) == explicit
    and #clicked.options == 1 and clicked.additions == 1,
    "explicit row rebinding remains idempotent")

local plainMenu = T.menu()
local plain = T.vanillaOption(plainMenu, worldObjects, T.patient)
Context.ensureCompanionMedicalOption(plainMenu, worldObjects, T.doctor)
check(plain.onSelect == Context.onMedicalCheck and plain.target == worldObjects
    and plain.param1 == T.doctor and plain.param2 == T.patient and #plainMenu.options == 1,
    "unwrapped legacy native options still bind the exact patient without duplicates")

local probeMenu = T.menu()
local probe = T.vanillaOption(probeMenu, worldObjects, T.patient, nil, true)
local probeTooltip = probe.toolTip
Context.fillWorldObjectContextMenu(0, probeMenu, worldObjects, true)
check(probe.param1 == originalCallback and probe.toolTip == probeTooltip and probe.notAvailable,
    "native menu test passes do not rewrite actionable patient options")

local conflictingRow = { id = T.selected.id, name = T.selected.name, actor = T.selected }
local overlapMenu = T.menu()
local overlap = T.vanillaOption(overlapMenu, worldObjects, T.patient, nil, true)
Context.ensureCompanionMedicalOption(overlapMenu, worldObjects, T.doctor)
Context.ensureCompanionMedicalOption(overlapMenu, worldObjects, T.doctor, conflictingRow)
check(overlap.param4 == T.patient and overlap.param4 ~= conflictingRow.actor
    and overlap.param1 == Context.onMedicalCheck and overlap.onSelect == getUpWrapper
    and #overlapMenu.options == 1,
    "the later floor-row pass cannot replace native body-hit patient Jill with clicked Tess")
T.patient.square.y = 14
Context.ensureCompanionMedicalOption(overlapMenu, worldObjects, T.doctor, conflictingRow)
check(overlap.notAvailable and overlap.toolTip
    and overlap.toolTip.description == "Move within " .. SC.MedicalUI.RANGE .. " tiles of Jill Kelvin for a medical check.",
    "conflicting floor rows cannot change the authoritative patient's availability or readable name")
T.patient.square.y = 11
Context.ensureCompanionMedicalOption(overlapMenu, worldObjects, T.doctor, conflictingRow)
local openedBeforeOverlap = #T.opened
overlap.onSelect(overlap.target, overlap.param1, overlap.param2, overlap.param3, overlap.param4)
check(T.getUpAction and #T.opened == openedBeforeOverlap,
    "the native patient keeps its get-up action after both menu binding passes")
local overlapOpened = T.completeGetUp()
check(overlapOpened == true and #T.opened == openedBeforeOverlap + 1
    and T.opened[#T.opened].patient == T.patient
    and T.opened[#T.opened].doctor == T.doctor
    and SC.UI.instance.selectedId == T.selected.id,
    "selecting the overlapped option examines native patient A without changing selected companion B")

local humanOverlapMenu = T.menu()
local humanOverlap = T.vanillaOption(humanOverlapMenu, worldObjects, T.human, nil, true)
local humanOverlapTooltip = humanOverlap.toolTip
check(Context.ensureCompanionMedicalOption(humanOverlapMenu, worldObjects, T.doctor, conflictingRow) == nil
    and humanOverlap.param1 == originalCallback and humanOverlap.param3 == T.doctor
    and humanOverlap.param4 == T.human and humanOverlap.onSelect == getUpWrapper
    and humanOverlap.toolTip == humanOverlapTooltip and humanOverlap.notAvailable
    and #humanOverlapMenu.options == 1,
    "an explicit companion row cannot hijack a preexisting native human-player medical option")

check(Context.ensureCompanionMedicalOption(foreignMenu, worldObjects, T.doctor, clickedRow) == nil
    and foreign.param3 == otherRequester and foreign.param4 == T.patient
    and foreign.param1 == originalCallback and foreign.onSelect == getUpWrapper
    and foreign.toolTip == foreignTooltip and foreign.notAvailable
    and #foreignMenu.options == 1,
    "even the same explicit patient cannot replace another requester's native medical option")
check(Context.ensureCompanionMedicalOption(unrelatedMenu, worldObjects, T.doctor, clickedRow) == nil
    and unrelated.param1 == unknown and unrelated.param4 == T.patient
    and unrelated.toolTip == unrelatedTooltip and #unrelatedMenu.options == 1,
    "an explicit companion row cannot replace an unrelated callback sharing the medical label")

SC_TEST_REPORT = "Medical context native-patient rebinding: " .. T.checks .. " checks passed"
