# SPDX-License-Identifier: MIT
# Ordered production files and observable cases; the shared runner owns execution.
@{ Name = 'interface-bug-report-draft'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Shared 'SCCall.lua'),
    (Join-Path $Shared 'SCConfig.lua'),
    (Join-Path $Shared 'SCDiagnostics.lua'),
    (Join-Path $Client 'SCBugReport.lua'),
    (Join-Path $UI 'SCBugReportDraftTests.lua')
) }
@{ Name = 'interface-bug-report-form'; Files = @(
    (Join-Path $UI 'SCBugReportFormFixture.lua'),
    (Join-Path $Client 'SCBugReportUI.lua'),
    (Join-Path $UI 'SCBugReportFormTests.lua')
) }
@{ Name = 'interface.medical-format'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCUIFormat.lua'),
    (Join-Path $UI 'SCUIFormatTests.lua')) }
@{ Name = 'interface.first-hour-guidance'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCGuidance.lua'),
    (Join-Path $Core 'guidance_harness.lua'),
    (Join-Path $Client 'SCGuidance.lua'),
    (Join-Path $Core 'guidance_harness.lua')
) }
@{ Name = 'interface.guidance-surfaces'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCUIGuidance.lua'),
    (Join-Path $UI 'SCUIGuidanceTests.lua')
) }
@{ Name = 'interface.emma-first-session'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCTerminalLines.lua'),
    (Join-Path $Client 'SCTerminalKnowledge.lua'),
    (Join-Path $Client 'SCTerminalConversation.lua'),
    (Join-Path $Client 'SCTerminalBrain.lua'),
    (Join-Path $Core 'guidance_emma_harness.lua')
) }
$interfacePanelFiles = @(
    (Join-Path $UI 'SCUIBasePolicyFixture.lua'),
    (Join-Path $Client 'SCContextMenu.lua'),
    (Join-Path $GameRoot 'media\lua\shared\ISBaseObject.lua'),
    (Join-Path $GameRoot 'media\lua\client\ISUI\ISUIElement.lua'),
    (Join-Path $GameRoot 'media\lua\client\ISUI\ISTickBox.lua'),
    (Join-Path $Client 'SCUIFormat.lua'),
    (Join-Path $Client 'SCUIBounds.lua'),
    (Join-Path $Client 'SCActionFeedback.lua'),
    (Join-Path $Client 'SCUIAttention.lua'),
    (Join-Path $Client 'SCUISocial.lua'),
    (Join-Path $Client 'SCUI.lua'),
    (Join-Path $Essential 'interface_commands.lua'),
    (Join-Path $UI 'SCUIAttentionTests.lua'),
    (Join-Path $UI 'SCUIBaseRefreshTests.lua'),
    (Join-Path $UI 'SCUICrisisControlsTests.lua'),
    (Join-Path $UI 'SCUISocialTests.lua'),
    (Join-Path $UI 'SCHomeTripObservationTests.lua'),
    (Join-Path $Client 'SCExpeditionTargets.lua'),
    (Join-Path $Client 'SCExpeditionMap.lua'),
    (Join-Path $UI 'SCExpeditionMapLayoutTests.lua')
)
@{ Name = 'interface-selected-and-cached'; Files = $interfacePanelFiles }
@{ Name = 'interface-expedition-panel'; Files = @(
    (Join-Path $UI 'SCUIExpeditionZoomFixture.lua'),
    (Join-Path $Client 'SCUIFormat.lua'),
    (Join-Path $Client 'SCUIExpeditions.lua'),
    (Join-Path $UI 'SCUIExpeditionZoomTests.lua')
) }

$interfaceContextFiles = @(
    (Join-Path $UI 'SCMedicalContextFixture.lua'),
    (Join-Path $GameRoot 'media\lua\shared\ISBaseObject.lua'),
    (Join-Path $GameRoot 'media\lua\server\BuildingObjects\ISBuildingObject.lua'),
    (Join-Path $GameRoot 'media\lua\client\ISUI\ISContextMenu.lua'),
    (Join-Path $Client 'SCContextMenu.lua'),
    (Join-Path $Client 'SCMedicalUI.lua'),
    (Join-Path $Client 'SCUIContext.lua')
)
@{ Name = 'interface-context-menu-lifecycle'; Files = $interfaceContextFiles + @(
    (Join-Path $UI 'SCContextMenuTests.lua')
) }
@{ Name = 'interface-grid-radio-context'; Files = $interfaceContextFiles + @(
    (Join-Path $UI 'SCGridRadioContextTests.lua')
) }

$interfaceTerminalFiles = @((Join-Path $UI 'SCTerminalFixture.lua'),
    (Join-Path $Client 'SCContextMenu.lua'),
    (Join-Path $Shared 'SCEmmaCareData.lua'),
    (Join-Path $Shared 'SCEmmaCare.lua'))
foreach ($module in @(
    'SCTerminalLines', 'SCTerminalKnowledge', 'SCTerminalConversation', 'SCTerminalBrain',
    'SCEmmaLanguageData', 'SCEmmaWords', 'SCEmmaSurvivalData', 'SCEmmaSurvival',
    'SCEmmaFollowups', 'SCEmmaMindData', 'SCEmmaMind', 'SCEmmaReadingsData', 'SCEmmaBody',
    'SCOddballForecast', 'SCEmmaCalendar', 'SCEmmaReadings', 'SCEmmaConversation', 'SCEmmaHooks', 'SCEmmaReferenceData', 'SCEmmaReference', 'SCEmmaMeaningData', 'SCEmmaMeaning', 'SCEmmaExchange', 'SCEmmaAnswers', 'SCEmmaContext', 'SCEmmaUnderstand', 'SCEmmaMissed', 'SCEmmaTerminal',
    'SCTerminalLore', 'SCTerminalFiles', 'SCTerminalPresentation', 'SCTerminalBusinessData',
    'SCTerminalBrands', 'SCTerminalArtBounds', 'SCTerminalSystem', 'SCControlUtil', 'SCUIBridge', 'SCEmmaJump',
    'SCTerminalPersona', 'SCTerminalPersonaSpiffy', 'SCTerminalPersonaEllis', 'SCTerminalPersonaDuty',
    'SCTerminalPersonaDiscovery', 'SCTerminalPersonaUI', 'SCTerminalLockState', 'SCTerminalLockWords',
    'SCTerminalLockSearch', 'SCTerminalLockPhysical', 'SCTerminalLockCardData', 'SCTerminalLockCard', 'SCTerminalLockCardUI',
    'SCTerminalLockWheelData', 'SCTerminalLockWheel', 'SCTerminalLockWheelUI',
    'SCTerminalLockEmmaData', 'SCTerminalLockEmma', 'SCTerminalLockPhone', 'SCTerminalLockRadio',
    'SCTerminalLockRival', 'SCTerminalLockStoryData', 'SCTerminalLockStory', 'SCTerminalLockCrack',
    'SCTerminalLockCase', 'SCTerminalLockCrew', 'SCTerminalLockStashes', 'SCTerminalDrawers',
    'SCTerminalPayoff', 'SCTerminalLockArt', 'SCTerminalLockUI', 'SCTerminalLocks',
    'SCTerminalWorld', 'SCTerminalLamp', 'SCTerminalActions', 'SCTerminal'
)) {
    $interfaceTerminalFiles += Join-Path $Client ($module + '.lua')
}
@{ Name = 'interface-building-services'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $Client 'SCBuildingControls.lua'),
    (Join-Path $Client 'SCBuildingScan.lua'),
    (Join-Path $Client 'SCTerminalHardware.lua'),
    (Join-Path $Client 'SCTerminalRadio.lua'),
    (Join-Path $Client 'SCRadioEndpoints.lua'),
    (Join-Path $Client 'SCGeneratorServices.lua'),
    (Join-Path $Client 'SCBuildingSecurity.lua'),
    (Join-Path $Client 'SCBuildingCircuits.lua'),
    (Join-Path $Client 'SCExpeditionTargets.lua'),
    (Join-Path $Client 'SCTerminalServices.lua'),
    (Join-Path $UI 'SCBuildingServicesTests.lua')
) }
@{ Name = 'interface-terminal-locks'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $UI 'SCTerminalLocksTests.lua')
) }
@{ Name = 'interface-terminal-access-and-keys'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $UI 'SCTerminalLockCardTests.lua'),
    (Join-Path $UI 'SCTerminalLockCardUITests.lua'),
    (Join-Path $UI 'SCTerminalLockCardDirectorTests.lua'),
    (Join-Path $UI 'SCTerminalActionTests.lua'),
    (Join-Path $UI 'SCTerminalLockPhase2Tests.lua'),
    (Join-Path $UI 'SCTerminalLockPhase3Tests.lua'),
    (Join-Path $UI 'SCTerminalConversationTests.lua'),
    (Join-Path $UI 'SCEmmaConversationTests.lua'),
    (Join-Path $UI 'SCEmmaMindTests.lua'),
    (Join-Path $UI 'SCEmmaReadingsTests.lua'),
    (Join-Path $Client 'SCRuntime.lua'),
    (Join-Path $Essential 'interface_terminal_idle.lua')
) }
@{ Name = 'interface-emma-corpus'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $UI 'SCEmmaCorpusData.lua'),
    (Join-Path $UI 'SCEmmaCorpusTests.lua'),
    (Join-Path $Gameplay 'emma_talk_care_harness.lua'),
    (Join-Path $UI 'SCEmmaCareSetGData.lua'),
    (Join-Path $Gameplay 'emma_care_set_g_harness.lua')
) }
@{ Name = 'interface-emma-care-fallback'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $Gameplay 'emma_care_fallback_harness.lua')
) }
@{ Name = 'interface-emma-talk-polish'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $UI 'SCEmmaTalkPolishData.lua'),
    (Join-Path $UI 'SCEmmaTalkPolishFixture.lua'),
    (Join-Path $UI 'SCEmmaTalkPolishBaseline.lua'),
    (Join-Path $UI 'SCEmmaBlindTests.lua'),
    (Join-Path $Gameplay 'emma_talk_polish_harness.lua'),
    (Join-Path $Gameplay 'lock_talk_polish_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_questions_harness.lua'),
    (Join-Path $Gameplay 'emma_hooks_harness.lua'),
    (Join-Path $Gameplay 'emma_reference_harness.lua'),
    (Join-Path $Gameplay 'emma_context_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_chat_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind2_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind3_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind4_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind5_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind6_harness.lua'),
    (Join-Path $Gameplay 'emma_talk_blind7_harness.lua')
) }

# These six harnesses specify the base parser/archive API, predating EMMA's
# deliberate overrides. Keep their original module isolation. Production EMMA
# routing and care run above with the full load order and the public corpora.
$interfaceBaseTerminalFiles = @((Join-Path $UI 'SCTerminalFixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'), (Join-Path $Shared 'SCSpeechColors.lua'))
foreach ($module in @('SCTerminalLines', 'SCTerminalKnowledge', 'SCTerminalConversation',
    'SCTerminalBrain', 'SCTerminalLore', 'SCTerminalFiles', 'SCTerminalPresentation',
    'SCTerminalBusinessData', 'SCTerminalBrands', 'SCTerminalArtBounds', 'SCTerminalSystem', 'SCTerminalWorld')) {
    $interfaceBaseTerminalFiles += Join-Path $Client ($module + '.lua')
}
foreach ($name in @('terminal_harness', 'terminal_system_harness', 'terminal_lore_harness',
    'terminal_knowledge_harness', 'terminal_conversation_harness', 'terminal_grid_harness')) {
    @{ Name = ('interface-base-' + $name); Files = @($interfaceBaseTerminalFiles) + @((Join-Path $Gameplay ($name + '.lua'))) }
}
@{ Name = 'interface-persona-conversations'; Files = @($interfaceTerminalFiles) + @((Join-Path $Gameplay 'persona_harness.lua')) }

$interfaceRadioFiles = @($interfaceTerminalFiles)
foreach ($module in @('SCTerminalHardware', 'SCTerminalRadio', 'SCTerminalRadioWorkUI', 'SCTerminalRadioUI', 'SCTerminalServices', 'SCRadioWork')) {
    $interfaceRadioFiles += Join-Path $Client ($module + '.lua')
}
@{ Name = 'interface-radio-lifecycle'; Files = $interfaceRadioFiles + @(
    (Join-Path $UI 'SCTerminalRadioTests.lua')
) }
