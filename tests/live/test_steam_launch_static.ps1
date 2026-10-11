# SPDX-License-Identifier: MIT

$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) '..\scripts\Invoke-LiveSandboxTests.ps1'
$runner = [System.IO.Path]::GetFullPath($runner)
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $runner, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Live runner PowerShell syntax error: $($parseErrors[0].Message)"
}

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($name in @('Test-CachedirLaunchArgument', 'Get-SteamLaunchedClient')) {
    $definition = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $name
    }, $true)
    Assert ($null -ne $definition) "Missing Steam launch helper: $name"
    . ([scriptblock]::Create($definition.Extent.Text))
}

$source = [System.IO.File]::ReadAllText($runner)
Assert ($source.Contains('[switch]$SteamLaunch')) 'Steam launch must be opt-in.'
Assert ($source.Contains('-applaunch 108600 ')) 'Steam must launch Project Zomboid app 108600.'
Assert ($source.Contains('Start-Process @startOptions')) 'Direct launch must remain available.'
Assert ($source.Contains('Stop-OwnedSandboxProcess $process')) 'Cleanup must use the bound game PID.'
Assert ($source.Contains('launchMode = if ($SteamLaunch)')) 'Run manifest must record the launch mode.'

$cache = 'C:\Test Runs\SC-Harness-1\cache'
$other = 'C:\Test Runs\SC-Harness-2\cache'
$goodArg = '"C:\Games\ProjectZomboid64.exe" -cachedir="' + $cache + '" -nosound'
$steamArg = '"C:\Games\ProjectZomboid64.exe" "-cachedir=' + $cache + '" ' +
    '-nosound -novoip "-debuglog=+General,+Lua"'
Assert (Test-CachedirLaunchArgument $goodArg $cache) 'Quoted cachedir must match.'
Assert (Test-CachedirLaunchArgument $steamArg $cache) `
    'Steam quoting the entire cachedir argument must match.'
Assert (Test-CachedirLaunchArgument ('game.exe -cachedir=' + $cache) $cache) `
    'Unquoted cachedir must match.'
Assert (-not (Test-CachedirLaunchArgument $goodArg $other)) 'Another run must not match.'
Assert (-not (Test-CachedirLaunchArgument ($steamArg.Replace($cache, $cache + '-extra')) $cache)) `
    'A Steam-quoted cachedir prefix must not match.'
Assert (-not (Test-CachedirLaunchArgument `
    ('game.exe -cachedir="' + $cache + '-extra" -nosound') $cache)) `
    'A cachedir prefix must not match.'

$gameExe = 'C:\Games\ProjectZomboid64.exe'
$script:mockProcesses = @()
$script:mockCim = @()
$script:denyCim = $false
function Get-Process {
    param($Name, $ErrorAction)
    return $script:mockProcesses
}
function Get-CimInstance {
    param($ClassName, $Filter, $ErrorAction)
    if ($script:denyCim) { throw 'Synthetic WMI denial' }
    return $script:mockCim
}

$client = [pscustomobject]@{ Id = 101; Path = $gameExe }
$script:mockProcesses = @($client)
$script:mockCim = @([pscustomobject]@{
    ProcessId = 101
    ExecutablePath = $gameExe
    CommandLine = $goodArg
})
$console = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('sc-steam-launch-' + [guid]::NewGuid().ToString('N') + '.txt')
$launchedAt = [DateTime]::UtcNow.AddSeconds(-5)
try {
    $args = @{
        ExistingProcessIds = @()
        ExpectedExecutable = $gameExe
        ExpectedCacheRoot = $cache
        ConsolePath = $console
        LaunchUtc = $launchedAt
    }
    $found = Get-SteamLaunchedClient @args
    Assert ($null -ne $found -and $found.Id -eq 101) `
        'A new game PID with the isolated cachedir must bind.'

    $args.ExistingProcessIds = @(101)
    Assert ($null -eq (Get-SteamLaunchedClient @args)) `
        'A preexisting game PID must never bind.'
    $args.ExistingProcessIds = @()

    $script:mockCim[0].CommandLine = 'game.exe -cachedir="' + $other + '"'
    Assert ($null -eq (Get-SteamLaunchedClient @args)) `
        'A game launched into another cachedir must never bind.'
    $script:mockCim[0].CommandLine = $goodArg
    $script:mockCim[0].ExecutablePath = 'C:\OtherGame\ProjectZomboid64.exe'
    Assert ($null -eq (Get-SteamLaunchedClient @args)) `
        'A game from a different install must never bind.'
    $script:mockCim[0].ExecutablePath = $gameExe

    $script:denyCim = $true
    Assert ($null -eq (Get-SteamLaunchedClient @args)) `
        'Without WMI, a fresh isolated console is required before binding.'
    [System.IO.File]::WriteAllText($console, 'new game console')
    [System.IO.File]::SetLastWriteTimeUtc($console, $launchedAt.AddSeconds(-5))
    Assert ($null -eq (Get-SteamLaunchedClient @args)) `
        'A stale console must not authorize ownership of a new PID.'
    [System.IO.File]::SetLastWriteTimeUtc($console, [DateTime]::UtcNow)
    $found = Get-SteamLaunchedClient @args
    Assert ($null -ne $found -and $found.Id -eq 101) `
        'A unique new PID plus fresh isolated console must bind without WMI.'
    $script:mockProcesses = @($client, [pscustomobject]@{ Id = 102; Path = $gameExe })
    Assert ($null -eq (Get-SteamLaunchedClient @args)) `
        'Console fallback must refuse ambiguous new game PIDs.'
    $script:denyCim = $false
    $script:mockCim += [pscustomobject]@{
        ProcessId = 102
        ExecutablePath = $gameExe
        CommandLine = $goodArg
    }
    $script:mockCim[0].CommandLine = $goodArg
    $ambiguous = $false
    try { $null = Get-SteamLaunchedClient @args } catch { $ambiguous = $true }
    Assert $ambiguous 'Two game PIDs with the same cachedir must be rejected.'
} finally {
    Remove-Item -LiteralPath $console -ErrorAction SilentlyContinue
}

Write-Output 'Steam launch static and process-ownership checks passed.'
