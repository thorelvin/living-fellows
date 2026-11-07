# SPDX-License-Identifier: MIT
# Ordered production files and observable cases; the shared runner owns execution.
@{ Name = 'interface.first-hour-guidance'; Files = @(
    (Join-Path $Core 'core_fixture.lua'),
    (Join-Path $Shared 'SCNamespace.lua'),
    (Join-Path $Client 'SCGuidance.lua'),
    (Join-Path $Core 'guidance_harness.lua'),
    (Join-Path $Client 'SCGuidance.lua'),
    (Join-Path $Core 'guidance_harness.lua')
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
    (Join-Path $Client 'SCUI.lua'),
    (Join-Path $Essential 'interface_commands.lua'),
    (Join-Path $UI 'SCUIBaseRefreshTests.lua'),
    (Join-Path $UI 'SCHomeTripObservationTests.lua'),
    (Join-Path $Client 'SCExpeditionTargets.lua'),
    (Join-Path $Client 'SCExpeditionMap.lua'),
    (Join-Path $UI 'SCExpeditionMapLayoutTests.lua')
)
@{ Name = 'interface-selected-and-cached'; Files = $interfacePanelFiles }

$interfaceContextFiles = @(
    (Join-Path $UI 'SCMedicalContextFixture.lua'),
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
    (Join-Path $Client 'SCContextMenu.lua'))
foreach ($module in @(
    'SCTerminalLines', 'SCTerminalKnowledge', 'SCTerminalConversation', 'SCTerminalBrain',
    'SCTerminalLore', 'SCTerminalFiles', 'SCTerminalPresentation', 'SCTerminalBusinessData',
    'SCTerminalBrands', 'SCTerminalArtBounds', 'SCTerminalSystem', 'SCControlUtil',
    'SCTerminalPersona', 'SCTerminalPersonaSpiffy', 'SCTerminalPersonaEllis', 'SCTerminalPersonaDuty',
    'SCTerminalPersonaDiscovery', 'SCTerminalPersonaUI', 'SCTerminalLockState', 'SCTerminalLockWords',
    'SCTerminalLockSearch', 'SCTerminalLockWheelData', 'SCTerminalLockWheel', 'SCTerminalLockWheelUI',
    'SCTerminalLockEmmaData', 'SCTerminalLockEmma', 'SCTerminalLockPhone', 'SCTerminalLockRadio',
    'SCTerminalLockRival', 'SCTerminalLockStoryData', 'SCTerminalLockStory', 'SCTerminalLockCrack',
    'SCTerminalLockCase', 'SCTerminalLockCrew', 'SCTerminalLockStashes', 'SCTerminalDrawers',
    'SCTerminalPayoff', 'SCTerminalLockArt', 'SCTerminalLockUI', 'SCTerminalLocks',
    'SCTerminalWorld', 'SCTerminalLamp', 'SCTerminalActions', 'SCTerminal'
)) {
    $interfaceTerminalFiles += Join-Path $Client ($module + '.lua')
}
@{ Name = 'interface-terminal-access-and-keys'; Files = @($interfaceTerminalFiles) + @(
    (Join-Path $UI 'SCTerminalActionTests.lua'),
    (Join-Path $UI 'SCTerminalLockPhase2Tests.lua'),
    (Join-Path $UI 'SCTerminalLockPhase3Tests.lua'),
    (Join-Path $Client 'SCRuntime.lua'),
    (Join-Path $Essential 'interface_terminal_idle.lua')
) }

$interfaceRadioFiles = @($interfaceTerminalFiles)
foreach ($module in @('SCTerminalHardware', 'SCTerminalRadio', 'SCTerminalRadioUI', 'SCTerminalServices')) {
    $interfaceRadioFiles += Join-Path $Client ($module + '.lua')
}
@{ Name = 'interface-radio-lifecycle'; Files = $interfaceRadioFiles + @(
    (Join-Path $UI 'SCTerminalRadioTests.lua')
) }
