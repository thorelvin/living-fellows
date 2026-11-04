# SPDX-License-Identifier: MIT
# Shared process policy for tests and per-invocation compilation receipts.
. (Join-Path $PSScriptRoot 'ScParallel.ps1')

function Invoke-ScTestCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$LogPath,
        [string]$WorkingDirectory = '',
        [int]$TimeoutSeconds = 600
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $FilePath
    $info.Arguments = ($Arguments | ForEach-Object { ConvertTo-ScCommandLineArgument $_ }) -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    if ($WorkingDirectory) { $info.WorkingDirectory = $WorkingDirectory }
    $caps = '-Xmx256m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC'
    $info.EnvironmentVariables['JAVA_TOOL_OPTIONS'] = $caps
    $info.EnvironmentVariables['JDK_JAVA_OPTIONS'] = $caps
    $info.EnvironmentVariables['SC_TEST_JOBS'] = '1'
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    try { $process.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
    if ([IO.Path]::GetFileNameWithoutExtension($FilePath) -eq 'java') { $script:ScTestJvmStarts++ }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true) } catch {
            # .NET Framework/Windows PowerShell 5.1 has no Kill(entireTree).
            # Kill our numeric child PID and descendants before draining pipes.
            $killInfo = New-Object Diagnostics.ProcessStartInfo
            $killInfo.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            $killInfo.Arguments = "/PID $($process.Id) /T /F"
            $killInfo.UseShellExecute = $false
            $killInfo.CreateNoWindow = $true
            $killInfo.RedirectStandardOutput = $true
            $killInfo.RedirectStandardError = $true
            $killer = [Diagnostics.Process]::Start($killInfo)
            $null = $killer.StandardOutput.ReadToEndAsync()
            $null = $killer.StandardError.ReadToEndAsync()
            if (-not $killer.WaitForExit(5000)) { $killer.Kill() }
            $killer.Dispose()
        }
        if (-not $process.WaitForExit(5000)) { throw "Timed-out child could not be stopped: $($process.Id)" }
        # An inherited pipe must not turn a bounded timeout into another hang.
        try { $null = $stdout.Wait(5000); $null = $stderr.Wait(5000) } catch { }
        $output = if ($stdout.Status -eq 'RanToCompletion') { $stdout.GetAwaiter().GetResult() } else { 'Output did not drain after timeout.' }
        if ($stderr.Status -eq 'RanToCompletion') { $output += $stderr.GetAwaiter().GetResult() }
        [IO.File]::WriteAllText($LogPath, $output)
        $process.Dispose()
        throw "Timed out after $TimeoutSeconds seconds. Evidence: $LogPath"
    }
    $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    $process.Dispose()
    [IO.File]::WriteAllText($LogPath, $output)
    if ($exitCode -ne 0) {
        $tail = ($output -split '\r?\n' | Where-Object {
            $_ -notmatch '^(NOTE: )?Picked up (JAVA_TOOL_OPTIONS|JDK_JAVA_OPTIONS):'
        } | Select-Object -Last 28) -join "`n"
        throw "Command exited $exitCode. Evidence: $LogPath`n$tail"
    }
}

function Get-ScLuaCompilationKey {
    param([string]$ProjectRoot, [string]$GameRoot)
    $luaRoot = Join-Path $ProjectRoot 'SurvivorCompanion\42\media\lua'
    $inputs = @(
        (Join-Path $GameRoot 'projectzomboid.jar'),
        (Join-Path $ProjectRoot 'tests\ui\ReflectLuaCompiler.java')
    ) + @(Get-ChildItem -LiteralPath $luaRoot -Recurse -File -Filter '*.lua' |
        Sort-Object FullName | ForEach-Object FullName)
    $lines = foreach ($path in $inputs) {
        $full = [IO.Path]::GetFullPath($path)
        "$full=$((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash)"
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))).Replace('-', '')
    } finally { $sha.Dispose() }
}

function Test-ScLuaCompilationReceipt {
    param([object]$Receipt, [string]$ProjectRoot, [string]$GameRoot)
    return $null -ne $Receipt -and $Receipt.Normal -eq $true -and $Receipt.Debug -eq $true `
        -and $Receipt.Key -eq (Get-ScLuaCompilationKey $ProjectRoot $GameRoot)
}
