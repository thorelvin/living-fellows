# Native camp observation, 0.27.21

Phase H used a disposable copy of the retained Main Camp kitchen save from
`SC-Harness-20261109-203142-6499a9d1`. The current user save was not loaded or
modified. The isolated source bridge did not replace the installed game JAR.
The observer records accepted companion overhead speech and existing action
state. It does not move actors, assign orders, change health, inject events or
change zombie navigation. Normal resident work continues.

The first attempt exposed a real Kahlua error: `tonumber(select(1, ...))`
forwarded the utility wrapper's success boolean as a numeric-base argument.
The clock reader now explicitly takes one return value. Both scene harnesses
provide a numeric native-style `getMinutesPerDay`, so the old expression fails
in a regression check rather than hiding behind an absent getter.

The corrected eleven-minute normal-speed observation passed all ten native
checks (`SC-Harness-20261115-043207-45d8e5c5`). One four-beat comfort scene
completed, with two speakers and no unsupported claims. A later opener did not
complete before the observation ended. A captured native frame shows the camp
and real overhead reply with the LF menus closed. This was a ninety-minute day,
not the simulator's sixty-minute setting.

A supplemental 400-second speed-two observation passed all eleven checks
(`SC-Harness-20261115-044842-bd9517d3`). It completed another four-beat comfort
scene. Two other scenes yielded to normal work: one to `voice.job.start.store`,
one to an owned `encounter:scavenge` action after its third beat. These are
expected interruptions: dialogue must not take ownership away from work.
Starts stayed at least three active real minutes apart despite accelerated
game time. Neither corrected run reported a Lua exception.

Native coverage establishes engine loading, clock conversion, real speech,
scene completion, work preemption and camp cadence. This old camp did not
exercise detailed historical recall or a death aftermath. Their evidence
remains the focused recall checks and the strict sixty-day simulation; this
observation does not claim native coverage of those paths.

## Accepted scene transcript

Normal speed:

> Tess Nolan: I'm tired of feeling like I have to earn every quiet minute.
>
> Jill Kelvin: I'll stay a while. You don't have to find the right words.
>
> Tess Nolan: Thank you for staying.
>
> Jill Kelvin: We can leave it quiet for a bit.

Supplemental speed two:

> Sanghwa Kim: I don't have much conversation in me. I don't want to sit alone, either.
>
> Jill Kelvin: Then we'll sit. Nothing else required.
>
> Sanghwa Kim: Thank you for staying.
>
> Jill Kelvin: One breath, then the next. The conversation can wait.

Interrupted route scene, before scavenging resumed:

> Sanghwa Kim: I'd rather take the long road home than argue with a short one full of teeth.
>
> Xian Burton: The long way has blind corners too. I'd want a look at both.
>
> Sanghwa Kim: Fair. Two routes, and neither gets our blind trust.

The disposable run folders retain the complete public-NPC-only transcript,
fifteen-second action samples and native screenshots. The versioned helper is
`tests/live/companion_voice_observer.lua`; it is not a shipped mod module.

All five release checks pass after the correction:
`build/test-results/20261115-050300-9f0334` (461.5 seconds), including the strict
sixty-day simulation and all computer, care, save and interface checks.
