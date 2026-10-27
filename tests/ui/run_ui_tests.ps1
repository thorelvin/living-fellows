# SPDX-License-Identifier: MIT

[CmdletBinding()]
param([string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')

$ErrorActionPreference = 'Stop'
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $TestRoot '..\..')).Path
$Client = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua\client'
$Jar = Join-Path $GameRoot 'projectzomboid.jar'
$GameJava = Join-Path $GameRoot 'jre64\bin\java.exe'
$Javac = & (Join-Path $ProjectRoot 'scripts\Resolve-TestJavac.ps1')
$BuildRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sc-ui-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $BuildRoot -Force | Out-Null
try {
    & $Javac -d $BuildRoot (Join-Path $ProjectRoot 'tests\gameplay\KahluaTestRunner.java')
    if ($LASTEXITCODE -ne 0) { throw 'UI Kahlua runner compilation failed.' }
    $files = @(
        (Join-Path $Client 'SCUIFormat.lua'),
        (Join-Path $TestRoot 'SCUIFormatTests.lua'),
        (Join-Path $Client 'SCUIBridge.lua'),
        (Join-Path $TestRoot 'SCUIBridgeTests.lua'),
        (Join-Path $Client 'SCMedicalUI.lua'),
        (Join-Path $TestRoot 'SCMedicalUITests.lua'),
        (Join-Path $TestRoot 'SCBaseVisualsFixture.lua'),
        (Join-Path $Client 'SCBaseVisuals.lua'),
        (Join-Path $TestRoot 'SCBaseVisualsTests.lua'),
        (Join-Path $Client 'SCConstructionPlanner.lua'),
        (Join-Path $TestRoot 'SCConstructionPlannerTests.lua'),
        (Join-Path $TestRoot 'SCBuildRecipeFixture.lua'),
        (Join-Path $Client 'SCBaseWork.lua'),
        (Join-Path $TestRoot 'SCBuildRecipeTests.lua'),
        (Join-Path $TestRoot 'SCCompanionMapFixture.lua'),
        (Join-Path $Client 'SCCompanionMap.lua'),
        (Join-Path $TestRoot 'SCCompanionMapTests.lua'),
        (Join-Path $TestRoot 'SCInteractionFixture.lua'),
        (Join-Path $Client 'SCInteraction.lua'),
        (Join-Path $TestRoot 'SCInteractionTests.lua')
    )
    Push-Location -LiteralPath $GameRoot
    try {
        $userOptionsFiles = @(
            (Join-Path $TestRoot 'SCUserOptionsFixture.lua'),
            (Join-Path $GameRoot 'media\lua\client\PZAPI\ModOptions.lua'),
            (Join-Path $Client 'SCUserOptions.lua'),
            (Join-Path $TestRoot 'SCUserOptionsTests.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @userOptionsFiles
        if ($LASTEXITCODE -ne 0) { throw 'User options Kahlua tests failed.' }
        $basePolicyFiles = @(
            (Join-Path $TestRoot 'SCUIBasePolicyFixture.lua'),
            (Join-Path $GameRoot 'media\lua\shared\ISBaseObject.lua'),
            (Join-Path $GameRoot 'media\lua\client\ISUI\ISUIElement.lua'),
            (Join-Path $GameRoot 'media\lua\client\ISUI\ISTickBox.lua'),
            (Join-Path $Client 'SCUIFormat.lua'),
            (Join-Path $Client 'SCUI.lua'),
            (Join-Path $TestRoot 'SCUIBasePolicyTests.lua'),
            (Join-Path $TestRoot 'SCUIBaseRefreshTests.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @basePolicyFiles
        if ($LASTEXITCODE -ne 0) { throw 'Base policy checkbox UI tests failed.' }
        $medicalContextFiles = @(
            (Join-Path $TestRoot 'SCMedicalContextFixture.lua'),
            (Join-Path $GameRoot 'media\lua\client\ISUI\ISContextMenu.lua'),
            (Join-Path $Client 'SCMedicalUI.lua'),
            (Join-Path $Client 'SCUIContext.lua'),
            (Join-Path $TestRoot 'SCMedicalContextTests.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @medicalContextFiles
        if ($LASTEXITCODE -ne 0) { throw 'Medical context native-patient rebinding tests failed.' }
        $storageContextFiles = @($medicalContextFiles | Select-Object -SkipLast 1)
        $storageContextFiles += Join-Path $TestRoot 'SCStorageContextTests.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @storageContextFiles
        if ($LASTEXITCODE -ne 0) { throw 'Storage context removal tests failed.' }
        $terminalContextFiles = @($medicalContextFiles | Select-Object -SkipLast 1)
        $terminalContextFiles += Join-Path $TestRoot 'SCTerminalContextTests.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @terminalContextFiles
        if ($LASTEXITCODE -ne 0) { throw 'Camp computer menu hook tests failed.' }
        $terminalFiles = @(
            (Join-Path $TestRoot 'SCTerminalFixture.lua'),
            (Join-Path $Client 'SCTerminalLines.lua'),
            (Join-Path $Client 'SCTerminalKnowledge.lua'),
            (Join-Path $Client 'SCTerminalBrain.lua'),
            (Join-Path $Client 'SCTerminalLore.lua'),
            (Join-Path $Client 'SCTerminalFiles.lua'),
            (Join-Path $Client 'SCTerminalPresentation.lua'),
            (Join-Path $Client 'SCTerminalBusinessData.lua'),
            (Join-Path $Client 'SCTerminalBrands.lua'),
            (Join-Path $Client 'SCTerminalArtBounds.lua'),
            # Auto-discovery can revisit a module already required by bootstrap.
            (Join-Path $Client 'SCTerminalBrands.lua'),
            (Join-Path $Client 'SCTerminalSystem.lua'),
            (Join-Path $Client 'SCTerminalWorld.lua'),
            (Join-Path $Client 'SCTerminalActions.lua'),
            (Join-Path $Client 'SCTerminal.lua'),
            (Join-Path $TestRoot 'SCTerminalTests.lua'),
            (Join-Path $TestRoot 'SCTerminalSystemTests.lua'),
            (Join-Path $TestRoot 'SCTerminalPresentationTests.lua'),
            (Join-Path $TestRoot 'SCTerminalAudioTests.lua'),
            (Join-Path $TestRoot 'SCTerminalActionTests.lua'),
            (Join-Path $TestRoot 'SCTerminalLoreTests.lua'),
            (Join-Path $TestRoot 'SCTerminalCompanionTests.lua'),
            (Join-Path $TestRoot 'SCTerminalReadingTests.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @terminalFiles
        if ($LASTEXITCODE -ne 0) { throw 'Camp computer terminal UI tests failed.' }
        $buildingFiles = @($terminalFiles | Where-Object { $_ -notmatch 'Tests\.lua$' })
        foreach ($module in @('SCControlUtil','SCBuildingControls','SCTerminalHardware','SCRadioEndpoints',
            'SCGeneratorServices','SCBuildingSecurity','SCBuildingCircuits','SCTerminalServices')) {
            $buildingFiles += Join-Path $Client ($module + '.lua')
        }
        $buildingFiles += Join-Path $TestRoot 'SCBuildingServicesTests.lua'
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @buildingFiles
        if ($LASTEXITCODE -ne 0) { throw 'Building services and station ownership tests failed.' }
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @files
        if ($LASTEXITCODE -ne 0) { throw 'UI Kahlua tests failed.' }
        $baseRedrawFiles = @(
            (Join-Path $TestRoot 'SCBaseVisualsFixture.lua'),
            (Join-Path $Client 'SCBaseVisuals.lua'),
            (Join-Path $TestRoot 'SCBaseVisualsRedrawTests.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @baseRedrawFiles
        if ($LASTEXITCODE -ne 0) { throw 'Base overlay UI redraw tests failed.' }
        $expeditionZoomFiles = @(
            (Join-Path $TestRoot 'SCUIExpeditionZoomFixture.lua'),
            (Join-Path $Client 'SCUIFormat.lua'),
            (Join-Path $Client 'SCUIExpeditions.lua'),
            (Join-Path $TestRoot 'SCUIExpeditionZoomTests.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @expeditionZoomFiles
        if ($LASTEXITCODE -ne 0) { throw 'Expedition zoom UI tests failed.' }
        $nicknameFiles = @(
            (Join-Path $Client 'SCNames.lua'),
            (Join-Path $Client 'SCUIBridge.lua'),
            (Join-Path $Client 'SCBanter.lua'),
            (Join-Path $TestRoot 'nickname_display_harness.lua')
        )
        & $GameJava -cp "$BuildRoot;$Jar" KahluaTestRunner @nicknameFiles
        if ($LASTEXITCODE -ne 0) { throw 'Nickname UI Kahlua tests failed.' }
    }
    finally {
        Pop-Location
    }
    & python (Join-Path $TestRoot 'test_ui_contract.py')
    if ($LASTEXITCODE -ne 0) { throw 'UI contract tests failed.' }
}
finally {
    if (Test-Path -LiteralPath $BuildRoot) {
        $resolved = [System.IO.Path]::GetFullPath($BuildRoot)
        $temporary = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporary, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe UI-test cleanup: $resolved"
        }
        Remove-Item -LiteralPath $BuildRoot -Recurse -Force
    }
}
