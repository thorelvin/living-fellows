# SPDX-License-Identifier: MIT

param(
    [string]$Helper = (Join-Path $PSScriptRoot '..\..\scripts\ActiveModList.ps1')
)

$ErrorActionPreference = 'Stop'
. $Helper

$checks = 0
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-Profile([string]$Actual, [string]$Expected, [string]$Description) {
    $script:checks++
    if ($Actual -cne $Expected) { $failures.Add($Description) }
}

$windows = @(
    'VERSION = 1,', '', 'mods', '{', '',
    '    mod = SurvivorCompanionAddon,',
    '    mod = SurvivorCompanion,',
    '    MOD = \SurvivorCompanion,', '',
    '    mod = survivorcompanion,',
    '    mod = \LivingFellows,',
    '}', '', 'maps', '{', '    map = SurvivorCompanion,', '}',
    'MOD = \SurvivorCompanion,', ''
) -join "`r`n"
$cleanWindows = $windows.Replace("    mod = SurvivorCompanion,`r`n", '').Replace(
    "    MOD = \SurvivorCompanion,`r`n", '')

Assert-Profile (Remove-ModEntry $windows 'SurvivorCompanion') $cleanWindows `
    'Remove every exact legacy entry, including an escaped value and capitalized key, while preserving prefixes, case variants, maps, blank lines and outside values.'
Assert-Profile (Add-ModEntry $cleanWindows 'LivingFellows') $cleanWindows `
    'An existing escaped canonical ID must be left intact without a duplicate.'
Assert-Profile (Remove-ModEntry $cleanWindows 'NoSuchMod') $cleanWindows `
    'Removing an absent ID must preserve the whole profile.'

$unix = "VERSION = 1,`nmods {`n`tmod = livingfellows,`n`tmod = Mod.Version,`n`tmod = ModXVersion,`n}`n"
$withCanonical = $unix.Replace("mods {`n", "mods {`n    mod = LivingFellows,`n")
Assert-Profile (Add-ModEntry $unix 'LivingFellows') $withCanonical `
    'Adding an exact ID must preserve LF and the first original row even when a case variant exists.'
Assert-Profile (Add-ModEntry $withCanonical 'LivingFellows') $withCanonical `
    'Adding an already present bare ID must preserve the whole profile.'
Assert-Profile (Remove-ModEntry $unix 'Mod.Version') ($unix.Replace("`tmod = Mod.Version,`n", '')) `
    'An exclusion ID containing a dot must be treated literally.'

$inline = 'VERSION = 1, mods { mod = \SurvivorCompanion, mod = Keep, MOD = SurvivorCompanion, } maps { map = Sample, }'
$cleanInline = 'VERSION = 1, mods { mod = Keep, } maps { map = Sample, }'
Assert-Profile (Remove-ModEntry $inline 'SurvivorCompanion') $cleanInline `
    'Removing an inline first and last entry must retain their sibling and its separator.'
Assert-Profile (Add-ModEntry $cleanInline 'LivingFellows') `
    ($cleanInline.Replace('mods {', 'mods { mod = LivingFellows,')) `
    'Adding to a single-line block must preserve its layout.'

$mixed = "VERSION = 1,`nmods { mod = Keep, mod = SurvivorCompanion,`n`tmod = Other,`n}`n"
Assert-Profile (Remove-ModEntry $mixed 'SurvivorCompanion') ($mixed.Replace(' mod = SurvivorCompanion,', '')) `
    'Removing an inline entry must preserve the next line break.'

$commented = @(
    'VERSION = 1,',
    '/* Example of an inactive block:',
    'mods { mod = SurvivorCompanion, }',
    '*/',
    'mods /* Keep header {note} */ {',
    '    /* Keep this example {',
    '    mod = SurvivorCompanion,',
    '    /* Nested example: mod = LivingFellows, */',
    '    } */',
    '    mod = \SurvivorCompanion /* old ID } */,',
    '    MOD = \LivingFellows /* canonical ID */,',
    '    mod = Keep,',
    '}', ''
) -join "`r`n"
$cleanCommented = $commented.Replace("    mod = \SurvivorCompanion /* old ID } */,`r`n", '')
Assert-Profile (Remove-ModEntry $commented 'SurvivorCompanion') $cleanCommented `
    'Remove an entry with an attached comment while retaining inactive examples verbatim.'
Assert-Profile (Add-ModEntry $cleanCommented 'LivingFellows') $cleanCommented `
    'An active escaped entry with a comment must prevent adding a duplicate.'
$commentOnly = $cleanCommented.Replace("    MOD = \LivingFellows /* canonical ID */,`r`n", '')
Assert-Profile (Add-ModEntry $commentOnly 'LivingFellows') `
    ($commentOnly.Replace("{`r`n    /* Keep this", "{`r`n    mod = LivingFellows,`r`n    /* Keep this")) `
    'A mention of an ID inside a comment must not suppress adding an active entry.'
$separateNote = "VERSION = 1,`nmods {`n    mod = SurvivorCompanion /* old */`n    , /* Keep this separate note */`n}`n"
Assert-Profile (Remove-ModEntry $separateNote 'SurvivorCompanion') `
    ($separateNote.Replace("    mod = SurvivorCompanion /* old */`n    ,", '')) `
    'A comment after the delimiter is separate from the removed entry.'

$leadingNotes = "VERSION = 1,`nmods { /* First */ mod = SurvivorCompanion, mod = Keep, " +
    "/* Second */ mod = SurvivorCompanion,`n    /* Third */ mod = SurvivorCompanion,`n}`n"
Assert-Profile (Remove-ModEntry $leadingNotes 'SurvivorCompanion') `
    ($leadingNotes.Replace(' mod = SurvivorCompanion,', '')) `
    'Leading inline comments after the block opener, a comma or a newline must remain intact.'
$canonicalAfterNote = 'VERSION = 1, mods { /* Leave me */ mod = \LivingFellows, mod = Keep, }'
Assert-Profile (Add-ModEntry $canonicalAfterNote 'LivingFellows') $canonicalAfterNote `
    'An existing ID after an inline comment must prevent adding a duplicate.'

# Build 42's ScriptParser records values at commas. A final ID without one does not load.
$unterminated = "VERSION = 1,`r`nmods`r`n{`r`n    mod = LivingFellows`r`n}`r`n"
Assert-Profile (Add-ModEntry $unterminated 'LivingFellows') `
    ($unterminated.Replace("{`r`n", "{`r`n    mod = LivingFellows,`r`n")) `
    'An unterminated final ID must not suppress adding a valid entry.'

if ($failures.Count -gt 0) { throw ("Sandbox mod-list checks failed:`n" + ($failures -join "`n")) }
Write-Output "SANDBOX_MOD_LIST_PASS checks=$checks"
