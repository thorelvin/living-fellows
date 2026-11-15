<!-- SPDX-License-Identifier: MIT -->
# Companion speech baseline

The authoritative run uses the actual game Kahlua VM and archived pre-V1
production sources from `a3e1f563`. It simulates 60 game days at 24 game hours
per real hour, with 43,200 ticks, eight save/load cycles, fights, a witnessed
death, expeditions, alarms and quiet camp time. No new companion text was added.

Actors are registered through the production registry interface and have
readable SurvivorDesc names. The initial exploratory fixture omitted registry
entries; that was corrected and the old sources replayed. Its earlier hash is
not used as the baseline. See `tests/fixtures/voice-soak/baseline.json` for the
source and fixture hashes.

| Metric | Before new speech |
|---|---:|
| Lines | 4,506 |
| Specific event recall | 0 |
| Exact repeats within three game days (pools >=8) | 3,653 |
| Smallest repeat interval | 0.05 game days |
| Conversations | 1,078 |
| Two-beat conversations | 1,078 |
| Three-or-more beats | 0 |
| Scripted events / group aftermaths | 26 / 0 |
| Speech hash | 1537253361 |

Legacy lines have no branch/tone tags. A zero tagged-tone count is not a claim
that the old speech meets the new grief rules. F/G must add the actual gates,
including their negative controls, aftermath coverage and cadence checks.

The readable sample week is [voice-soak-baseline-week.txt](voice-soak-baseline-week.txt).
It includes the day-20 death. The repeat problem is visible in ordinary camp
questions and routine remarks, across reloads.

Reproduce with `scripts/Test-VoiceSoak.ps1 -Baseline -SourceRef a3e1f563`.
Phase E must also pass `-Baseline -CompareBaseline` using the current sources.
The historical 0.27.18 community fixture was exported by that release's real
Kahlua modules, not constructed by the new restore code. Its community source
blob is identical to the pre-V1 release's (`c1fca762f63e176474cf829eb16e5a44ab760b62`).
