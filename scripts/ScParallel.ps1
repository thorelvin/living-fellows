# SPDX-License-Identifier: MIT
<#
Runs independent gate steps concurrently.

Every step here must be genuinely independent: the runner gives no ordering
guarantee and starts steps as soon as a slot frees up. A step that writes
anywhere another step reads does not belong in the same batch -- put it in an
earlier one.

Output is captured per step and replayed as a block when that step finishes, so
a parallel run reads like a serial one instead of interleaving several JVMs.
All failures are reported, not just the first: a gate that stops at the earliest
failure costs another full run to find the second.
#>

# No Set-StrictMode here on purpose: this file is dot-sourced into runners that
# were not written under it, and strict mode would change their semantics rather
# than only adding these functions.

<#
Start-Process joins -ArgumentList with spaces and quotes nothing, so a single
argument holding a space -- the Project Zomboid install path, every time --
silently becomes two arguments and the step dies on startup. Quote each
argument the way the Windows command line parser expects before handing the
list over.
#>
function ConvertTo-ScCommandLineArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    if ($Value -eq '') { return '""' }
    if ($Value.Contains('"')) {
        # Every argument a gate step takes is a path or a flag. Rather than
        # reimplement the full CommandLineToArgvW escape, refuse the case and
        # keep the quoting provably correct for the ones that do occur.
        throw "Gate step arguments must not contain a double quote: $Value"
    }
    if ($Value -notmatch '\s') { return $Value }
    # A trailing backslash run would otherwise escape the closing quote.
    $trailing = 0
    while ($trailing -lt $Value.Length -and
           $Value[$Value.Length - 1 - $trailing] -eq '\') { $trailing++ }
    return '"' + $Value + ('\' * $trailing) + '"'
}

function New-ScStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [string]$Failure = ''
    )
    if ([string]::IsNullOrWhiteSpace($Failure)) { $Failure = "$Name failed." }
    [pscustomobject]@{
        Name             = $Name
        FilePath         = $FilePath
        Arguments        = $Arguments
        WorkingDirectory = $WorkingDirectory
        Failure          = $Failure
    }
}

<#
Spawn the same PowerShell host that is running, rather than hardcoding
powershell.exe.

PSModulePath is inherited, and pwsh's does not contain the Windows PowerShell
5.1 module directories. A 5.1 child launched from pwsh therefore cannot load
Microsoft.PowerShell.Utility, and ordinary cmdlets -- Get-FileHash was the one
that surfaced it -- fail with CommandNotFoundException. Source CI runs
`shell: pwsh`, so every spawned step died there while passing on a developer
machine whose shell is 5.1. Matching the host keeps the module path coherent
whichever way round it is.
#>
function Get-ScPowerShellHost {
    try {
        $path = (Get-Process -Id $PID).Path
        if (-not [string]::IsNullOrWhiteSpace($path) -and
            (Test-Path -LiteralPath $path -PathType Leaf)) {
            return $path
        }
    } catch { }
    return 'powershell.exe'
}

function New-ScPowerShellStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Script,
        [string[]]$Arguments = @(),
        [string]$Failure = ''
    )
    New-ScStep -Name $Name -FilePath (Get-ScPowerShellHost) -Failure $Failure -Arguments (
        @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Script) + $Arguments)
}

function Invoke-ScParallelSteps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Steps,
        [int]$Throttle = 4,
        [string]$Label = 'steps',
        [switch]$Quiet
    )

    if ($Steps.Count -eq 0) { return }
    if ($Throttle -lt 1) { $Throttle = 1 }

    $captureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('sc-parallel-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $captureRoot -Force | Out-Null

    $pending = [System.Collections.Generic.Queue[object]]::new()
    foreach ($step in $Steps) { $pending.Enqueue($step) }
    $running = New-Object System.Collections.ArrayList
    $failures = New-Object System.Collections.ArrayList
    $completed = 0
    $index = 0
    $overall = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        while ($pending.Count -gt 0 -or $running.Count -gt 0) {
            while ($pending.Count -gt 0 -and $running.Count -lt $Throttle) {
                $step = $pending.Dequeue()
                $index++
                $outPath = Join-Path $captureRoot "$index.out"
                $errPath = Join-Path $captureRoot "$index.err"
                $startArgs = @{
                    FilePath               = $step.FilePath
                    NoNewWindow            = $true
                    PassThru               = $true
                    RedirectStandardOutput = $outPath
                    RedirectStandardError  = $errPath
                }
                if ($step.Arguments.Count -gt 0) {
                    $startArgs.ArgumentList = @($step.Arguments |
                        ForEach-Object { ConvertTo-ScCommandLineArgument $_ })
                }
                if (-not [string]::IsNullOrWhiteSpace($step.WorkingDirectory)) {
                    $startArgs.WorkingDirectory = $step.WorkingDirectory
                }
                $process = Start-Process @startArgs
                # Touching Handle caches the native handle in the .NET object.
                # Without it the handle is closed when the child exits and
                # ExitCode comes back empty, which reads as a failed step even
                # though the step passed.
                $null = $process.Handle
                [void]$running.Add([pscustomobject]@{
                    Step    = $step
                    Process = $process
                    Out     = $outPath
                    Err     = $errPath
                    Clock   = [System.Diagnostics.Stopwatch]::StartNew()
                })
            }

            Start-Sleep -Milliseconds 120

            for ($i = $running.Count - 1; $i -ge 0; $i--) {
                $entry = $running[$i]
                if (-not $entry.Process.HasExited) { continue }
                # Flush the redirected streams before the captures are read.
                $entry.Process.WaitForExit()
                $entry.Clock.Stop()
                $running.RemoveAt($i)
                $completed++
                $code = $entry.Process.ExitCode
                $ok = ($code -eq 0)
                $seconds = $entry.Clock.Elapsed.TotalSeconds

                if (-not $Quiet) {
                    $status = if ($ok) { 'PASS' } else { "FAIL exit=$code" }
                    Write-Host ("[{0}/{1}] {2,-28} {3,7:N1}s {4}" -f `
                        $completed, $Steps.Count, $entry.Step.Name, $seconds, $status)
                }
                foreach ($capture in @($entry.Out, $entry.Err)) {
                    if (-not (Test-Path -LiteralPath $capture)) { continue }
                    $text = (Get-Content -LiteralPath $capture -Raw)
                    if ([string]::IsNullOrWhiteSpace($text)) { continue }
                    # A passing step's chatter is noise; its result lines are not.
                    # A failing step gets everything, because that is the log the
                    # failure has to be diagnosed from.
                    if ($ok -and -not $Quiet) {
                        # Result lines only. "OK <path>" is the Lua compile gate
                        # reporting every payload file, which is hundreds of
                        # lines of noise once a step has already said it passed.
                        $text.TrimEnd() -split "`r?`n" |
                            Where-Object { $_ -match '_PASS\b|PASS:|^\s*OK\s*$' } |
                            ForEach-Object { Write-Host "    $_" }
                    }
                    elseif (-not $ok) {
                        $text.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Host "    $_" }
                    }
                }
                if (-not $ok) {
                    [void]$failures.Add("$($entry.Step.Failure) (exit $code)")
                }
            }
        }
    }
    finally {
        foreach ($entry in $running) {
            if (-not $entry.Process.HasExited) {
                try { $entry.Process.Kill() } catch { }
            }
        }
        $resolved = [System.IO.Path]::GetFullPath($captureRoot)
        $temporary = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($temporary, [System.StringComparison]::OrdinalIgnoreCase) -or
            -not ((Split-Path -Leaf $resolved) -like 'sc-parallel-*')) {
            throw "Refusing cleanup outside the owned capture directory: $resolved"
        }
        if (Test-Path -LiteralPath $resolved) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }

    $overall.Stop()
    if (-not $Quiet) {
        Write-Host ("{0}: {1} of {2} passed in {3:N1}s (throttle {4})" -f `
            $Label, ($Steps.Count - $failures.Count), $Steps.Count,
            $overall.Elapsed.TotalSeconds, $Throttle)
    }
    if ($failures.Count -gt 0) {
        throw ("{0} failed:`n  {1}" -f $Label, ($failures -join "`n  "))
    }
}
