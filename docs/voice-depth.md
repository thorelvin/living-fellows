<!-- SPDX-License-Identifier: MIT -->

# Voice depth

Implementation of `C:/ZOMBOID/plan-voice-depth.md`, based on release 0.26.95
(`27057aa6`) in `feature/voice-depth`, for `living_fellows/0.26.95`.
Release metadata remains unchanged.

The four targeted areas now have 1,031 authored lines across 97 topics. This
adds the supplied 455 lines and another 195 to meet the explicit depth floor:
at least eight eligible lines for every personality voice and mood mix. There
are 17 new topics, and the ten specified stiff replies have been rewritten.
Tone stays short, human, dry and dark, with printable ASCII and clean twins
for profanity. Fills are rendered before the 18-word check.

New context follows existing actions:

- Camp calls choose recent-repeat, then night (21:00-05:00), then fog or heavy
  rain, then the ordinary alarm level. Fall-back is never replaced. All-clear
  distinguishes accepted combat actions from an uneventful passing contact.
- During an alarm, a newly wounded resident can be called out once by an
  awake witness on the same floor, within ten meters and with line of sight.
  Medical checks are cached and limited to once a second; pure combat-state
  reads do not advance or cancel actions. The accepted-offense timestamp
  survives kill confirmation and no-target cleanup.
- Talk reports rest from 68% fatigue, after illness, wounds, thirst and hunger.
  Camp residents discuss camp when on base duty or present there, after the
  danger branch. The actual describer supplies fatigue to both status and
  relationship summaries.
- Uniforms and good clothes affect hauling remarks; pyre lighting at night
  (20:00-05:00) and digging in rain of at least 0.3 get their own lines.
- Verified physical drops count a body once per camp/day. Counts five, ten,
  fifteen, twenty, thirty, forty and fifty may replace the usual drop line.
  The milestone's 100% chance still respects the ordinary actor cooldown,
  party gap and silence near threats. No second bark is added.
- Studying another outfit group already studied that day can recall it. The
  group is remembered only when the study finishes; aborted approaches do not
  count. Night and rain add weight-two middle candidates; study duration, curiosity,
  cooldowns and number of lines remain unchanged.

Missing contextual pools fall back to existing topics or the established Talk
fallback text. A missing world clock does not invent daily memory. The shared
world reader reuses the existing ambient clock and weather interfaces.

Optional `voiceDay` data is saved inside each existing camp: a day, a bounded
hauling counter and at most 24 outfit-group entries. It is normalized on load
and reset on day rollover without changing the save version. A body's bounded
`LF_HaulVoiceReceipts` prevents repeated drops from inflating a camp's count.
Voice bookkeeping does not change work revisions or rebuild the Base menu.
There is no new background service, house scan, inventory search or native
bridge change.

Four supplied lines were adjusted to avoid false context: an injured resident
is not automatically described as down; July does not become August; repeated
outfits after the second are called "another" rather than always "second".

Verification is recorded in `validation-voice-depth.md`. Local installation
and guide publication are separate from this Lua update.
