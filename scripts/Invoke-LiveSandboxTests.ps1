# SPDX-License-Identifier: MIT

[CmdletBinding()]
param(
    [string]$ProjectRoot = '',
    [string]$GameRoot = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$UserCache = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'),
    [string]$SeedSave,
    [string]$GameMode,
    [ValidateRange(45, 600)]
    # Large mod lists can spend more than three minutes in script, map and
    # asset loading before Build 42 exposes its click-to-start gate. The
    # in-game harness retains its own bounded deadline once play begins.
    [int]$TimeoutSeconds = 300,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $scriptDirectory
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
$UserCache = [System.IO.Path]::GetFullPath($UserCache)
$RunsRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build\live-sandbox-runs'))
$runsPrefix = $RunsRoot.TrimEnd('\') + '\'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Test-ProjectZomboidRunning {
    $matches = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like 'ProjectZomboid*' -or
        ($_.Name -match '^java(w)?\.exe$' -and $_.CommandLine -match 'ProjectZomboid')
    })
    return $matches.Count -gt 0
}

function Add-ModEntry([string]$Text, [string]$ModId) {
    if ($Text -match ('(?m)^\s*mod\s*=\s*' + [regex]::Escape($ModId) + '\s*,?\s*$')) {
        return $Text
    }
    $pattern = New-Object regex '(?ms)(mods\s*\{\s*)'
    if (-not $pattern.IsMatch($Text)) { throw 'mods.txt has no mods block.' }
    $newline = [Environment]::NewLine
    return $pattern.Replace($Text, ('$1    mod = ' + $ModId + ',' + $newline), 1)
}

function Invoke-LoadingScreenClick([System.Diagnostics.Process]$Process) {
    if ($null -eq ('SCLiveHarness.WindowInput' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace SCLiveHarness {
    public static class WindowInput {
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr hWnd, out Rect rect);

        [StructLayout(LayoutKind.Sequential)]
        public struct Point {
            public int X;
            public int Y;
        }

        [DllImport("user32.dll")]
        private static extern bool ClientToScreen(IntPtr hWnd, ref Point point);

        [DllImport("user32.dll")]
        private static extern bool GetCursorPos(out Point point);

        [DllImport("user32.dll")]
        private static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern void mouse_event(uint flags, uint dx, uint dy,
            uint data, UIntPtr extraInfo);

        public static bool ClickClientCentre(IntPtr hWnd) {
            const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
            const uint MOUSEEVENTF_LEFTUP = 0x0004;
            Rect rect;
            if (hWnd == IntPtr.Zero || !GetClientRect(hWnd, out rect)) return false;
            Point original;
            if (!GetCursorPos(out original)) return false;
            Point centre = new Point {
                X = Math.Max(1, (rect.Right - rect.Left) / 2),
                Y = Math.Max(1, (rect.Bottom - rect.Top) / 2)
            };
            if (!ClientToScreen(hWnd, ref centre)) return false;
            SetForegroundWindow(hWnd);
            System.Threading.Thread.Sleep(250);
            if (!SetCursorPos(centre.X, centre.Y)) return false;
            mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
            System.Threading.Thread.Sleep(180);
            mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
            SetCursorPos(original.X, original.Y);
            return true;
        }
    }
}
'@
    }
    $Process.Refresh()
    if ($Process.HasExited -or $Process.MainWindowHandle -eq [IntPtr]::Zero) { return $false }
    return [SCLiveHarness.WindowInput]::ClickClientCentre($Process.MainWindowHandle)
}

if (Test-ProjectZomboidRunning) {
    throw 'Close Project Zomboid before preparing a real sandbox harness run.'
}

$gameExe = Join-Path $GameRoot 'ProjectZomboid64.exe'
$gameConfig = Join-Path $GameRoot 'ProjectZomboid64.json'
if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $gameConfig -PathType Leaf)) {
    throw "Project Zomboid client was not found under $GameRoot"
}
$launcher = Get-Content -LiteralPath $gameConfig -Raw -Encoding utf8 | ConvertFrom-Json
if ($launcher.mainClass -ne 'survivorcompanion/bridge/SCLauncher') {
    throw 'The native SCLauncher is not installed; run Install-Local.ps1 -NativeBridge first.'
}
$bridgeClassPath = @($launcher.classpath | Where-Object { $_ -match 'SurvivorCompanion.*Bridge.*\.jar' })
if ($bridgeClassPath.Count -ne 1) {
    throw 'ProjectZomboid64.json does not contain exactly one SurvivorCompanion bridge classpath entry.'
}
$bridgePath = $bridgeClassPath[0].Replace('/', '\')
if (-not [System.IO.Path]::IsPathRooted($bridgePath)) { $bridgePath = Join-Path $GameRoot $bridgePath }
if (-not (Test-Path -LiteralPath $bridgePath -PathType Leaf)) {
    throw "Native companion bridge is missing: $bridgePath"
}

$latestFile = Join-Path $UserCache 'latestSave.ini'
if ([string]::IsNullOrWhiteSpace($SeedSave)) {
    if (-not (Test-Path -LiteralPath $latestFile -PathType Leaf)) {
        throw 'No SeedSave was supplied and latestSave.ini does not exist.'
    }
    $latest = @(Get-Content -LiteralPath $latestFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($latest.Count -lt 2) { throw 'latestSave.ini must contain world and game mode.' }
    $seedName = $latest[0].Trim()
    if ([string]::IsNullOrWhiteSpace($GameMode)) { $GameMode = $latest[1].Trim() }
    $SeedSave = Join-Path (Join-Path (Join-Path $UserCache 'Saves') $GameMode) $seedName
}
$SeedSave = [System.IO.Path]::GetFullPath($SeedSave)
if ([string]::IsNullOrWhiteSpace($GameMode)) {
    $GameMode = Split-Path -Leaf (Split-Path -Parent $SeedSave)
}
if ($GameMode -notmatch '^[A-Za-z0-9 _-]{1,64}$') { throw "Unsafe game mode: $GameMode" }
if (-not (Test-Path -LiteralPath $SeedSave -PathType Container)) {
    throw "Seed save does not exist: $SeedSave"
}
$seedMods = Join-Path $SeedSave 'mods.txt'
$seedMap = Join-Path $SeedSave 'map_ver.bin'
if (-not (Test-Path -LiteralPath $seedMods -PathType Leaf) -or
    -not (Test-Path -LiteralPath $seedMap -PathType Leaf)) {
    throw 'Seed save must contain mods.txt and map_ver.bin.'
}

$runId = 'SC-Harness-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),
    ([guid]::NewGuid().ToString('N')).Substring(0, 8)
$RunRoot = [System.IO.Path]::GetFullPath((Join-Path $RunsRoot $runId))
if (-not $RunRoot.StartsWith($runsPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe live harness run root: $RunRoot"
}
$CacheRoot = Join-Path $RunRoot 'cache'
$SandboxMods = Join-Path $CacheRoot 'mods'
$SandboxLua = Join-Path $CacheRoot 'Lua\SurvivorCompanionHarness'
$SandboxSaves = Join-Path (Join-Path $CacheRoot 'Saves') $GameMode
$TargetSave = Join-Path $SandboxSaves $runId

New-Item -ItemType Directory -Path $SandboxMods,$SandboxLua,$SandboxSaves -Force | Out-Null

# Copy only user preferences needed to bypass first-run UI. Saves, logs, databases,
# and the real mod list remain outside the disposable cachedir.
foreach ($name in @('options.ini', 'options2.bin', 'debuglog.ini', 'keysB42.ini', 'version.txt')) {
    $source = Join-Path $UserCache $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $CacheRoot $name)
    }
}
$bindings = Join-Path $UserCache 'InputBindings'
if (Test-Path -LiteralPath $bindings -PathType Container) {
    Copy-Item -LiteralPath $bindings -Destination (Join-Path $CacheRoot 'InputBindings') -Recurse
}

# Clone the save before any game process starts. The source save is never opened by
# the test client because -cachedir redirects every save lookup into CacheRoot.
Copy-Item -LiteralPath $SeedSave -Destination $TargetSave -Recurse

# Expose existing local/Vortex mod payloads through read-only-use junctions. The
# sandbox owns only the junction objects; the runner never cleans or writes targets.
$realMods = Join-Path $UserCache 'mods'
if (Test-Path -LiteralPath $realMods -PathType Container) {
    foreach ($directory in Get-ChildItem -LiteralPath $realMods -Directory) {
        if ($directory.Name -eq 'SurvivorCompanion' -or
            $directory.Name -eq 'SCRealSandboxHarness') { continue }
        $link = Join-Path $SandboxMods $directory.Name
        if (-not (Test-Path -LiteralPath $link)) {
            New-Item -ItemType Junction -Path $link -Target $directory.FullName | Out-Null
        }
    }
}
$resetMarker = Join-Path $realMods 'reset-mods-42_00.txt'
if (-not (Test-Path -LiteralPath $resetMarker -PathType Leaf)) {
    throw 'Build 42 mod-reset marker is missing from the user mod directory.'
}
Copy-Item -LiteralPath $resetMarker -Destination (Join-Path $SandboxMods 'reset-mods-42_00.txt')

$privatePayloadRoot = Join-Path $RunRoot 'private-playtest-payload'
& (Join-Path $ProjectRoot 'scripts\New-PrivatePlaytestPayload.ps1') `
    -ProjectRoot $ProjectRoot -OutputRoot $privatePayloadRoot | Out-Null
$sourceMod = Join-Path $privatePayloadRoot 'SurvivorCompanion'
$harnessMod = Join-Path $ProjectRoot 'tests\live\mod\SCRealSandboxHarness'
if (-not (Test-Path -LiteralPath $sourceMod -PathType Container) -or
    -not (Test-Path -LiteralPath $harnessMod -PathType Container)) {
    throw 'Source mod or live harness mod is missing.'
}
Copy-Item -LiteralPath $sourceMod -Destination (Join-Path $SandboxMods 'SurvivorCompanion') -Recurse
Copy-Item -LiteralPath $harnessMod -Destination (Join-Path $SandboxMods 'SCRealSandboxHarness') -Recurse

$modText = Get-Content -LiteralPath $seedMods -Raw -Encoding utf8
$modText = Add-ModEntry $modText 'SurvivorCompanion'
$modText = Add-ModEntry $modText 'SCRealSandboxHarness'
[System.IO.File]::WriteAllText((Join-Path $SandboxMods 'default.txt'), $modText, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $TargetSave 'mods.txt'), $modText, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $CacheRoot 'latestSave.ini'),
    ($runId + [Environment]::NewLine + $GameMode + [Environment]::NewLine), $utf8NoBom)

$config = @(
    'enabled=true',
    'autoload=true',
    ('run_id=' + $runId),
    ('world=' + $runId),
    ('mode=' + $GameMode),
    ('internal_timeout_ms=' + (($TimeoutSeconds - 15) * 1000))
) -join [Environment]::NewLine
[System.IO.File]::WriteAllText((Join-Path $SandboxLua 'config.ini'),
    ($config + [Environment]::NewLine), $utf8NoBom)

$manifest = [ordered]@{
    schema = 1
    runId = $runId
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    seedSave = $SeedSave
    gameMode = $GameMode
    cacheRoot = $CacheRoot
    targetSave = $TargetSave
    sourceRelease = ((Get-Content -LiteralPath (Join-Path $sourceMod 'mod.info') |
        Where-Object { $_ -match '^modversion=' }) -replace '^modversion=', '')
    sourceSaveIsReadOnlyInput = $true
    autoCleanup = $false
}
[System.IO.File]::WriteAllText((Join-Path $RunRoot 'run-manifest.json'),
    ($manifest | ConvertTo-Json -Depth 4), $utf8NoBom)

$summaryPath = Join-Path $SandboxLua 'summary.txt'
$eventsPath = Join-Path $SandboxLua 'events.log'
$consolePath = Join-Path $CacheRoot 'console.txt'
Write-Output "Prepared isolated live sandbox: $RunRoot"
Write-Output "Source save remains untouched: $SeedSave"
if ($PrepareOnly) {
    Write-Output "LIVE_SANDBOX_PREPARED run=$runId cache=$CacheRoot"
    return
}

$argumentLine = '-cachedir="' + $CacheRoot + '" -nosound -novoip -debuglog=+General,+Lua'
$process = Start-Process -FilePath $gameExe -WorkingDirectory $GameRoot `
    -ArgumentList $argumentLine -PassThru
Write-Output "Started real Project Zomboid client test pid=$($process.Id)"

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$nextLoadingClick = [DateTime]::MaxValue
$loadingReadyObserved = $false
$clickAttempts = 0
while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    $process.Refresh()
    if ($process.HasExited) {
        throw "Live sandbox client exited before writing a summary (exit=$($process.ExitCode)). Run retained at $RunRoot"
    }
    if (-not $loadingReadyObserved -and (Test-Path -LiteralPath $consolePath -PathType Leaf)) {
        $loadingReadyObserved = Select-String -LiteralPath $consolePath `
            -SimpleMatch 'game loading took' -Quiet
        if ($loadingReadyObserved) {
            $nextLoadingClick = [DateTime]::UtcNow.AddMilliseconds(750)
            Write-Output 'World load completed; waiting for the Build 42 click-to-start gate.'
        }
    }
    if ($loadingReadyObserved -and [DateTime]::UtcNow -ge $nextLoadingClick -and
        -not (Test-Path -LiteralPath $eventsPath -PathType Leaf)) {
        $clickAttempts++
        if (Invoke-LoadingScreenClick $process) {
            Write-Output "Sent isolated click-to-start attempt $clickAttempts to pid=$($process.Id)"
        }
        $nextLoadingClick = [DateTime]::UtcNow.AddSeconds(3)
    }
    Start-Sleep -Milliseconds 500
}
if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
    throw "Live sandbox test timed out. Run retained at $RunRoot; inspect $consolePath and process $($process.Id)."
}

$summary = Get-Content -LiteralPath $summaryPath
$statusLine = $summary | Where-Object { $_ -match '^status=' } | Select-Object -First 1
$status = $statusLine -replace '^status=', ''
$exitDeadline = [DateTime]::UtcNow.AddSeconds(15)
while ([DateTime]::UtcNow -lt $exitDeadline) {
    $process.Refresh()
    if ($process.HasExited) { break }
    Start-Sleep -Milliseconds 250
}

Get-Content -LiteralPath $eventsPath -ErrorAction SilentlyContinue
Write-Output "Live sandbox run retained for audit: $RunRoot"
Write-Output "Live console: $consolePath"
if ($status -ne 'PASS') {
    throw "LIVE_SANDBOX_FAIL run=$runId results=$eventsPath"
}
Write-Output "LIVE_SANDBOX_PASS run=$runId results=$eventsPath"
