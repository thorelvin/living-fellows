# SPDX-License-Identifier: MIT

# The Oracle javapath shim on this host can spin indefinitely during `javac`
# (even for `-version`). Resolve an actual JDK binary and put its directory
# first on PATH so nested test scripts cannot accidentally launch that shim.
$candidates = @('C:\Program Files\Java\jdk-17\bin\javac.exe')
if (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
    $candidates += Join-Path $env:JAVA_HOME 'bin\javac.exe'
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
        if (($env:PATH -split ';')[0] -ne $bin) {
            $env:PATH = $bin + ';' + $env:PATH
        }
        Write-Output $resolved
        return
    }
}
throw 'A real JDK javac.exe is required; the Oracle javapath shim is unsupported.'
