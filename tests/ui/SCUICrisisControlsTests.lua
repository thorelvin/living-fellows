-- SPDX-License-Identifier: MIT
-- Public crisis controls must distinguish a current policy from releasing it,
-- and keep the exact decision snapshot on each callback.
local SC, UI = SurvivorCompanion, SurvivorCompanion.UI
local oldCrisis, oldRefresh = SC.InfectionCrisis, UI.refresh
local calls, refreshes = {}, 0
SC.InfectionCrisis = {
    choose=function(id,outcome,revision)
        calls[#calls+1]={id=id,outcome=outcome,revision=revision}
        if revision ~= 9 then return false,'crisis_decision_changed' end
        return true,{}
    end,
    release=function(id,reason,revision)
        calls[#calls+1]={id=id,reason=reason,revision=revision}
        return revision == 9
    end,
}
UI.refresh = function() refreshes=refreshes+1 end
local root = {selectedRow={id='another-companion'}}
local detail = BasePolicyFixture.classes.SCUIDetail:new(0,0,400,400,root)
local panel = ISPanel:new(0,0,400,400)
detail:addCrisisAction(panel,0,'UI_SC_Base_Outcome_watch','mike-crisis',
    'watch','choose',9,'Mike',true)
local selected = panel.childrenInOrder[#panel.childrenInOrder]
assert(selected.enable == false
    and selected.scLabel == 'UI_SC_Base_Outcome_watch_current'
    and selected.tooltip == 'UI_SC_Base_Outcome_watch_current_hint',
    'the current watch policy is visibly selected rather than an apparently inert choice')
detail:addCrisisAction(panel,50,'UI_SC_Base_Outcome_quarantine','mike-crisis',
    'quarantine','choose',9,'Mike')
local alternative = panel.childrenInOrder[#panel.childrenInOrder]
assert(alternative.enable == true, 'alternative policies remain available')
alternative.onClick(alternative.target,alternative)
assert(#calls == 1 and calls[1].id == 'mike-crisis'
    and calls[1].outcome == 'quarantine' and calls[1].revision == 9
    and detail.feedbackSuccess == true,
    'a subsequent choice dispatches the exact crisis and refreshed revision')
detail:addCrisisAction(panel,100,'UI_SC_Base_ReleaseCrisis','mike-crisis',
    nil,'release',9,'Mike')
local release = panel.childrenInOrder[#panel.childrenInOrder]
assert(release.enable == true, 'ending an already-watched crisis remains available')
release.onClick(release.target,release)
assert(#calls == 2 and calls[2].id == 'mike-crisis'
    and calls[2].reason == 'player_released' and calls[2].revision == 9
    and detail.feedbackSuccess == true,
    'returning to normal duty calls release, not another watch decision')
alternative.scDecisionRevision = 8
alternative.onClick(alternative.target,alternative)
assert(not detail.feedbackSuccess and refreshes == 3
    and SC.ActionFeedback.reason('crisis_decision_changed').kind == 'crisis_decision_changed',
    'a concurrently changed decision refreshes controls and explains the rejection')
SC.InfectionCrisis, UI.refresh = oldCrisis, oldRefresh
SC_TEST_REPORT = 'CRISIS_CONTROLS_PASS selected watch, alternative, exact revision, release and rejection feedback'
