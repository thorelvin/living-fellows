# SPDX-License-Identifier: MIT
[CmdletBinding()]
param([switch]$NegativeControls, [switch]$SkipMatrix)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $ProjectRoot ('build\test-results\intersection-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$java = 'C:\Program Files\Java\jdk-17\bin\java.exe'
$javac = 'C:\Program Files\Java\jdk-17\bin\javac.exe'
$classes = Join-Path $ProjectRoot 'build\native-bridge\classes'
$sourceRoot = Join-Path $ProjectRoot 'bridge\src\main\java\livingfellows\bridge'
$testRoot = Join-Path $ProjectRoot 'bridge\src\test\java\livingfellows\bridge'
$fixture = Join-Path $ProjectRoot 'tests\live\fixtures\intersection-phase0-42.22.2\junctions.tsv'
& (Join-Path $PSScriptRoot 'Build-NativeBridge.ps1') -ProjectRoot $ProjectRoot > (Join-Path $logs 'build.log')
if ($LASTEXITCODE -ne 0) { throw 'Native bridge build failed.' }
& $javac -cp $classes -d $logs (Join-Path $testRoot 'SCIntersectionTurnsTest.java') (Join-Path $testRoot 'SCRoadFollowerTest.java')
if ($LASTEXITCODE -ne 0) { throw 'Intersection test compilation failed.' }
function Run-Turn([string]$Label, [string]$ClassPath, [string]$Check, [string]$Class = 'SCIntersectionTurnsTest') {
    $argsList = @('-Xmx256m', '-XX:ActiveProcessorCount=2', '-XX:+UseSerialGC', "-DturnCheck=$Check",
        "-DturnFixturePath=$fixture", "-DturnReportDir=$logs")
    if ($SkipMatrix) { $argsList += '-DturnSmoke=true' }
    $argsList += @('-cp', $ClassPath, "livingfellows.bridge.$Class")
    $prior = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $java @argsList > (Join-Path $logs ($Label + '.log')) 2>&1
        return $LASTEXITCODE
    } finally { $ErrorActionPreference = $prior }
}
$positive = Run-Turn 'positive' "$logs;$classes" 'all'
$fingerprint = Run-Turn 'fingerprints' "$logs;$classes" 'all' 'SCRoadFollowerTest'
Get-Content (Join-Path $logs 'positive.log') | Where-Object { $_ -match '^TURN_MATRIX|^TURN_TIMING|^INTERSECTION_' } | Select-Object -Last 4
Get-Content (Join-Path $logs 'fingerprints.log') | Select-Object -Last 1
if ($fingerprint -ne 0) { throw "Unchanged driving commands regressed; see $logs" }
$mutations = @(
    @{Label='builder';File='SCDrivePath.java';Check='right';Needle='return SCCornerPathBuilder.build(original(), nextProfile, null);';Replacement='return original();';Expected='right lane error'},
    @{Label='total-angle';File='SCRoadFollower.java';Check='speed';Needle='float angle = Math.abs(corner.angle());';Replacement='float angle = corner.arc() ? 0 : Math.abs(corner.angle());';Expected='whole-corner speed limit'},
    @{Label='hold';File='SCRoadFollower.java';Check='hold';Needle='if (along > corner.end() && error < Math.toRadians(15))';Replacement='if (along > corner.end())';Expected='mid-turn speed holds'},
    @{Label='reverse';File='SCRoadFollower.java';Check='reverse';Needle='path.original().reversed().withCorners(profile)';Replacement='path.reversed()';Expected='reverse rebuild uses original route'},
    @{Label='steering';File='SCRoadFollower.java';Check='left';Needle='float blend = cornerSteeringBlend(lookAhead);';Replacement='float blend = 0;';Expected='left lane error'},
    @{Label='sides';File='SCCornerPathBuilder.java';Check='sides';Needle='V q = new V(x - originX, y - originY);';Replacement='if (Float.isFinite(x)) return true; V q = new V(x - originX, y - originY);';Expected='V2 rejects'},
    @{Label='fallback';File='SCRoadFollower.java';Check='wreck';Needle='if (limitedArc != null && !rebuildingCorner && sharpenCorner(limitedArc))';Replacement='if (false)';Expected='wreck arrives|wreck switches one corner'},
    @{Label='identity';File='SCCornerPathBuilder.java';Check='geometry';Needle='return new Node(point(root, index), root.width(index)';Replacement='return new Node(index == 1 ? point(root, index).add(new V(.01, 0)) : point(root, index), root.width(index)';Expected='straight-stretch identity'},
    @{Label='merge';File='SCRoadFollower.java';Check='merge';Needle='while (pieceEnd < arc.end() - 0.01f';Replacement='while (pieceEnd < at - 1 && pieceEnd < arc.end() - 0.01f';Expected='merged arc scan cost'},
    @{Label='short-scan';File='SCRoadFollower.java';Check='shortScan';Needle='if (chord <= 0.001f)';Replacement='if (false && chord <= 0.001f)';Expected='clipped arc scan stays clear'},
    @{Label='late-offset';File='SCRoadFollower.java';Check='lateOffset';Needle='if (limitedArc != null && limitedArc.start() - along < halfLength + 4';Replacement='if (false && limitedArc != null && limitedArc.start() - along < halfLength + 4';Expected='late offset avoids rear body collision'},
    @{Label='governor';File='SCDriveControl.java';Check='governor';Needle='holdGap, 0.15f, 0.25f';Replacement='holdGap, SPEED_UP_BELOW_KMH, BRAKE_ABOVE_KMH';Expected='corner governor holds requested speed'},
    @{Label='moving-entry';File='SCRoadFollower.java';Check='approach';Needle='float margin = speed * 0.1f;';Replacement='float margin = 1.5f + speed * 0.4f;';Expected='moving arc approach timing'},
    @{Label='bumper';File='SCRoadFollower.java';Check='bumper';Needle='if (bumperArc != null && frontClear >= 0';Replacement='if (false && bumperArc != null && frontClear >= 0';Expected='bumper corner fallback'},
    @{Label='corner-recovery';File='SCRoadFollower.java';Check='cornerRecovery';Needle='boolean cornerBlocked = !scanClear';Replacement='boolean cornerBlocked = false && !scanClear';Expected='corner bumper recovery'}
    @{Label='filled-strip';File='SCLaneScan.java';Check='filledStrip';Needle='lookAhead, kinds, true);';Replacement='lookAhead, kinds, false);';Expected='interior obstacle in corner route strip'},
    @{Label='bumper-motion';File='SCRoadFollower.java';Check='clearBumper';Needle='&& Math.abs(speedKmh) <= 1.0f';Replacement='&& true';Expected='clear arc does not sharpen for distant lamp'},
    @{Label='leg-width';File='SCCornerPathBuilder.java';Check='multiCorner';Needle='bend.inWidth = legWidth(root, first - 1, turning);';Replacement='bend.inWidth = root.width(first - 1) > 0 ? root.width(first - 1) : 6;';Expected='multi-corner lane continuity'},
    @{Label='turning-point';File='SCCornerPathBuilder.java';Check='multiCorner';Needle='if (turning[other]) return';Replacement='if (false) return';Expected='keeps its own lane'},
    @{Label='reverse-widths';File='SCDrivePath.java';Check='multiCorner';Needle='return new SCDrivePath(x, y, w, !widthsLeaveNode);';Replacement='return new SCDrivePath(x, y, w);';Expected='reversed lane='},
    @{Label='straight-lanes';File='SCDrivePath.java';Check='multiCorner';Needle='if (straightLanes != null) return straightLanes[segment];';Replacement='';Expected='after a sharp turn'}
)
if ($NegativeControls) {
    foreach ($mutation in $mutations) {
        $variant = Join-Path $logs $mutation.Label
        $src = Join-Path $variant 'src'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $files = foreach ($name in @('SCDrivePath.java', 'SCCornerPathBuilder.java', 'SCRoadFollower.java', 'SCDriveControl.java', 'SCLaneScan.java')) {
            $source = [IO.File]::ReadAllText((Join-Path $sourceRoot $name))
            if ($name -eq $mutation.File) {
                if ($source.IndexOf($mutation.Needle) -ne $source.LastIndexOf($mutation.Needle)) {
                    throw ($mutation.Label + ' mutation is not unique.')
                }
                $changed = $source.Replace($mutation.Needle, $mutation.Replacement)
                if ($changed -eq $source) { throw ($mutation.Label + ' did not change production code.') }
                $source = $changed
            }
            $file = Join-Path $src $name
            [IO.File]::WriteAllText($file, $source, [Text.UTF8Encoding]::new($false))
            $file
        }
        & $javac -cp $classes -d $variant @files > (Join-Path $variant 'compile.log') 2>&1
        if ($LASTEXITCODE -ne 0) { throw ($mutation.Label + ' did not compile; see ' + $variant) }
        $code = Run-Turn ($mutation.Label + '-negative') "$variant;$logs;$classes" $mutation.Check
        $output = [IO.File]::ReadAllText((Join-Path $logs ($mutation.Label + '-negative.log')))
        if ($code -eq 0 -or $output -notmatch $mutation.Expected) {
            throw ($mutation.Label + ' did not fail its named check; see ' + $logs)
        }
        Write-Output ($mutation.Label + ' EXPECTED_FAIL exit=' + $code)
    }
}
if ($positive -ne 0) { throw "Intersection acceptance failed; see $logs" }
Write-Output "INTERSECTION_TURNS_SUITE_PASS matrix=$(-not $SkipMatrix) negatives=$NegativeControls logs=$logs"
