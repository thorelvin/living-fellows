# SPDX-License-Identifier: MIT

# The Oracle javapath shim on this host can spin indefinitely during `javac`
# (even for `-version`). Resolve an actual JDK binary and put its directory
# first on PATH so nested test scripts cannot accidentally launch that shim.
# Tests compile against the real game JAR. Since 42.22 it uses Java 25 class
# files, so a Java 17/24 compiler cannot compile those tests. The independently
# built bridge keeps its Java 17 bytecode target for the game's newer JVM.
$runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\core\pz-runtime.json'
$runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
$requiredMajor = if ($runtime.javaMajor) { [int]$runtime.javaMajor } else { 17 }
$candidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:SC_TEST_JAVA_HOME)) {
    $candidates += Join-Path $env:SC_TEST_JAVA_HOME 'bin\javac.exe'
}
if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $candidates += Join-Path $env:JAVA_HOME 'bin\javac.exe'
}
foreach ($root in @('C:\Program Files\Java',
        (Join-Path $env:LOCALAPPDATA 'LivingFellowsDev\toolchains'))) {
    if (Test-Path -LiteralPath $root -PathType Container) {
        $candidates += @(Get-ChildItem -LiteralPath $root -Directory -Filter 'jdk-*' |
            Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'bin\javac.exe' })
    }
}
foreach ($directory in ($env:PATH -split ';')) {
    if ([string]::IsNullOrWhiteSpace($directory) -or
        $directory -match '(?i)Oracle[\\/]Java[\\/]javapath') { continue }
    $candidates += Join-Path $directory 'javac.exe'
}
foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $bin = Split-Path -Parent $resolved
        $release = Join-Path (Split-Path -Parent $bin) 'release'
        if (-not (Test-Path -LiteralPath $release -PathType Leaf)) { continue }
        $version = [regex]::Match((Get-Content -LiteralPath $release -Raw),
            '(?m)^JAVA_VERSION="(\d+)(?:[.\-"]|$)')
        if (-not $version.Success -or [int]$version.Groups[1].Value -ne $requiredMajor) { continue }
        if (($env:PATH -split ';')[0] -ne $bin) {
            $env:PATH = $bin + ';' + $env:PATH
        }
        Write-Output $resolved
        return
    }
}
throw "A real Java $requiredMajor JDK is required for the pinned game JAR. Set SC_TEST_JAVA_HOME to its directory; the Oracle javapath shim is unsupported."
