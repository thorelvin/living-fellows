[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$ReportPath,
    [int]$ConsoleTailLines = 12000
)

$ErrorActionPreference = 'Stop'

function Redact-LocalPaths {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $clean = $Text -replace '(?im)[A-Z]:\\Users\\[^\\\r\n]+', '<user-home>'
    $clean = $clean -replace '(?im)/Users/[^/\r\n]+', '<user-home>'
    $clean = $clean -replace '(?im)/home/[^/\r\n]+', '<user-home>'
    return $clean
}

function Get-StackClassification {
    param([string[]]$Lines)
    $labels = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $Lines) {
        if ($line -match '(?i)SurvivorCompanion|Living[ _-]?Fellows|media[/\\]lua[/\\](client|shared)[/\\]SC[A-Za-z]+\.lua') {
            [void]$labels.Add('living_fellows')
        }
        elseif ($line -match '(?i)(workshop[/\\]content|[/\\]mods[/\\]).*\.lua') {
            [void]$labels.Add('external_mod')
        }
        elseif ($line -match '(?i)(stack traceback|java\.|zombie\.|media[/\\]lua[/\\](client|shared)[/\\])') {
            [void]$labels.Add('vanilla/unknown')
        }
    }
    if ($labels.Count -eq 0) { [void]$labels.Add('vanilla/unknown') }
    return @($labels | Sort-Object)
}

$zomboidRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'
$desktopRoot = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $desktopRoot "Living-Fellows-Support-$stamp.zip"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'LivingFellowsSupport-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryRoot)

try {
    $consolePath = Join-Path $zomboidRoot 'console.txt'
    $selectedLines = @()
    if (Test-Path -LiteralPath $consolePath -PathType Leaf) {
        $selectedLines = @(Get-Content -LiteralPath $consolePath -Tail $ConsoleTailLines)
        $redactedConsole = Redact-LocalPaths ($selectedLines -join [Environment]::NewLine)
        Set-Content -LiteralPath (Join-Path $temporaryRoot 'console-recent.txt') `
            -Value $redactedConsole -Encoding UTF8
    }

    $logsArchive = Join-Path $zomboidRoot 'logs.zip'
    $redactedArchiveFiles = 0
    if (Test-Path -LiteralPath $logsArchive -PathType Leaf) {
        $expandedLogs = Join-Path $temporaryRoot 'recent-game-logs'
        [void](New-Item -ItemType Directory -Path $expandedLogs)
        $archiveScratch = Join-Path $temporaryRoot 'archive-scratch'
        Expand-Archive -LiteralPath $logsArchive -DestinationPath $archiveScratch
        $archivePrefix = $archiveScratch.TrimEnd([System.IO.Path]::DirectorySeparatorChar) `
            + [System.IO.Path]::DirectorySeparatorChar
        foreach ($source in Get-ChildItem -LiteralPath $archiveScratch -Recurse -File) {
            if ($source.Extension -notin @('.txt', '.log', '.json', '.xml')) { continue }
            $relative = $source.FullName.Substring($archivePrefix.Length)
            $destination = Join-Path $expandedLogs $relative
            $destinationParent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
                [void](New-Item -ItemType Directory -Path $destinationParent)
            }
            $sourceText = Get-Content -LiteralPath $source.FullName -Raw
            Set-Content -LiteralPath $destination -Value (Redact-LocalPaths $sourceText) -Encoding UTF8
            $redactedArchiveFiles++
        }
        Remove-Item -LiteralPath $archiveScratch -Recurse -Force
    }

    $reportText = $null
    if (-not [string]::IsNullOrWhiteSpace($ReportPath) -and
        (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
        $reportText = Get-Content -LiteralPath $ReportPath -Raw
    }
    elseif (Get-Command Get-Clipboard -ErrorAction SilentlyContinue) {
        $clipboardText = Get-Clipboard -Raw -ErrorAction SilentlyContinue
        if ($clipboardText -like 'Living Fellows support report*') {
            $reportText = $clipboardText
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($reportText)) {
        Set-Content -LiteralPath (Join-Path $temporaryRoot 'living-fellows-report.txt') `
            -Value (Redact-LocalPaths $reportText) -Encoding UTF8
    }

    $modIdentifiers = $selectedLines | ForEach-Object {
        if ($_ -match '(?i)(?:mod|mod id|loaded mod)\s*[:=]\s*([A-Za-z0-9_. -]{2,100})') {
            $matches[1].Trim()
        }
    } | Where-Object { $_ } | Sort-Object -Unique
    Set-Content -LiteralPath (Join-Path $temporaryRoot 'loaded-mod-identifiers.txt') `
        -Value @('# Extracted only from explicit mod-loader lines in console.txt.', $modIdentifiers) `
        -Encoding UTF8

    $classifications = Get-StackClassification $selectedLines
    Set-Content -LiteralPath (Join-Path $temporaryRoot 'stack-root-classification.txt') `
        -Value @(
            '# Evidence labels present in the collected console excerpt.',
            '# These labels do not assign unrelated errors to Living Fellows.',
            $classifications
        ) -Encoding UTF8

    $manifest = @(
        'Living Fellows support bundle',
        "Created: $((Get-Date).ToString('o'))",
        "Recent console included: $([bool]$selectedLines.Count)",
        "Redacted text logs extracted from logs.zip: $redactedArchiveFiles",
        "In-game support report included: $(-not [string]::IsNullOrWhiteSpace($reportText))",
        'Local user paths in collected text files were redacted.',
        'Binary and unsupported files from logs.zip were deliberately omitted.'
    )
    Set-Content -LiteralPath (Join-Path $temporaryRoot 'README.txt') -Value $manifest -Encoding UTF8

    $outputDirectory = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $outputDirectory)
    }
    Compress-Archive -Path (Join-Path $temporaryRoot '*') `
        -DestinationPath $resolvedOutput -CompressionLevel Optimal
    Write-Output $resolvedOutput
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    $resolvedSystemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemporaryRoot.StartsWith($resolvedSystemTemp,
        [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemporaryRoot -PathType Container)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}
