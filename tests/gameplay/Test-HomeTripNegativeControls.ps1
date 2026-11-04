# SPDX-License-Identifier: MIT
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$GameJava,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Classpath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$HomeTripFiles,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$HomeUiFiles,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$BuildRoot
)

$ErrorActionPreference = 'Stop'
$resolvedBuildRoot = [IO.Path]::GetFullPath($BuildRoot)
if (-not (Test-Path -LiteralPath $resolvedBuildRoot -PathType Container)) {
    throw "Home-trip negative-control build directory does not exist: $resolvedBuildRoot"
}
$buildPrefix = $resolvedBuildRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$utf8 = [Text.UTF8Encoding]::new($false)

# Source names, rather than positional assumptions, select the module in each
# runner. Every literal must occur exactly once before a mutant is written.
$mutants = @(
    @{
        Name = 'let-five-start'
        Files = $HomeTripFiles
        Harness = 'home_trip_harness.lua'
        SourceAnchor = 'blocked("home_too_many",{records=records})'
        Expected = 'expected blocker home_too_many'
        Changes = @(
            @{ File = 'SCHomeTrip.lua'; From = 'elseif #result.records>4 then result.blocker="home_too_many" end'; To = 'elseif #result.records>5 then result.blocker="home_too_many" end' },
            @{ File = 'SCHomeTrip.lua'; From = 'or type(records)~="table" or #records<1 or #records>4 then return false,"home_invalid_plan" end'; To = 'or type(records)~="table" or #records<1 or #records>5 then return false,"home_invalid_plan" end' },
            @{ File = 'SCExpeditionPrototype.lua'; From = 'if type(records) ~= "table" or #records < 1 or #records > 4 then'; To = 'if type(records) ~= "table" or #records < 1 or #records > 5 then' }
        )
    },
    @{
        Name = 'finish-without-followers'
        Files = $HomeTripFiles
        Harness = 'home_trip_harness.lua'
        SourceAnchor = 'leader alone cannot complete arrival'
        Expected = 'leader alone cannot complete arrival'
        Changes = @(
            @{ File = 'SCHomeTrip.lua'; From = 'if not inside(actor,home.camp.arrival) or not SC.BaseLife.isInside(actor) then return false,"home_member_not_home" end'; To = 'if actor==active.leader.actor and (not inside(actor,home.camp.arrival) or not SC.BaseLife.isInside(actor)) then return false,"home_member_not_home" end' }
        )
    },
    @{
        Name = 'drop-blocker-line'
        Files = $HomeUiFiles
        Harness = 'SCHomeTripUITests.lua'
        SourceAnchor = 'negative control: removing the red blocker must fail even when Send is disabled'
        Expected = 'negative control: removing the red blocker must fail even when Send is disabled'
        Changes = @(
            @{ File = 'SCUIHomeTrip.lua'; From = 'detail:addChild(label)'; To = '-- negative control: omit the visible blocker label' }
        )
    }
)

foreach ($mutant in $mutants) {
    $sources = @{}
    $runFiles = @($mutant.Files)
    $harnesses = @($runFiles | Where-Object { [IO.Path]::GetFileName($_) -eq $mutant.Harness })
    if ($harnesses.Count -lt 1) { throw "Missing intended assertion harness: $($mutant.Name)" }
    foreach ($harness in $harnesses) {
        $harnessText = [IO.File]::ReadAllText($harness)
        $sourceAnchorCount = [regex]::Matches($harnessText, [regex]::Escape($mutant.SourceAnchor)).Count
        if ($sourceAnchorCount -ne 1) {
            throw "Expected one intended assertion source anchor for $($mutant.Name); found $sourceAnchorCount."
        }
    }

    foreach ($change in $mutant.Changes) {
        $indices = @()
        for ($index = 0; $index -lt $runFiles.Count; $index++) {
            if ([IO.Path]::GetFileName($runFiles[$index]) -eq $change.File) { $indices += $index }
        }
        if ($indices.Count -ne 1) {
            throw "Expected one source index for $($mutant.Name)/$($change.File); found $($indices.Count)."
        }
        $source = [IO.Path]::GetFullPath($runFiles[$indices[0]])
        if (-not $sources.ContainsKey($source)) {
            $sources[$source] = @{
                Index = $indices[0]
                Text = [IO.File]::ReadAllText($source)
                Hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
            }
        }
        $entry = $sources[$source]
        $anchorCount = [regex]::Matches($entry.Text, [regex]::Escape($change.From)).Count
        if ($anchorCount -ne 1) {
            throw "Expected one mutation anchor for $($mutant.Name)/$($change.File); found $anchorCount."
        }
        $entry.Text = $entry.Text.Replace($change.From, $change.To)
    }

    foreach ($source in $sources.Keys) {
        $entry = $sources[$source]
        $target = [IO.Path]::GetFullPath((Join-Path $resolvedBuildRoot (
            'home-trip-mutant-' + $mutant.Name + '-' + [IO.Path]::GetFileName($source))))
        if (-not $target.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $target.Equals($source, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing a mutation outside the test build directory: $target"
        }
        [IO.File]::WriteAllText($target, $entry.Text, $utf8)
        $runFiles[$entry.Index] = $target
    }
    $log = Join-Path $resolvedBuildRoot ('home-trip-mutant-' + $mutant.Name + '.txt')
    $savedPreference = $ErrorActionPreference
    try {
        # A failing native process writes stderr by design. Windows PowerShell
        # 5.1 must not convert that expected stream into a terminating error.
        $ErrorActionPreference = 'Continue'
        & $GameJava -cp $Classpath KahluaTestRunner @runFiles *> $log
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
        foreach ($source in $sources.Keys) {
            if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $sources[$source].Hash) {
                throw "Negative control changed production source: $source"
            }
        }
    }
    $detail = [IO.File]::ReadAllText($log)
    $intendedAssertion = ($detail -match 'java\.lang\.AssertionError:' -and
        $detail.Contains($mutant.Harness) -and $detail.Contains($mutant.Expected))
    $compilerFailure = $detail -match 'LuaCompiler\.|LexState\.|syntax error|unexpected symbol|unfinished string'
    if ($code -eq 0 -or -not $intendedAssertion -or $compilerFailure) {
        throw "Home-trip negative control missed its intended assertion: $($mutant.Name); exit=$code log=$log"
    }
    Write-Output "HOME_TRIP_NEGATIVE_PASS mutant=$($mutant.Name) exit=$code assertion=$($mutant.Expected)"
}
