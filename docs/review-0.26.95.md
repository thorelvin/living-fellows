<!-- SPDX-License-Identifier: MIT -->

# 0.26.95 code review

Date: 2026-11-04. Base: `81f56a0f`, `living_fellows/0.26.95`.
Scope: the latest voice-depth commit and the preceding Send Home release,
including dialogue routing, corpse lifecycle, saved camp context and the
departure UI. These fixes and the packing work below ship in 0.26.96.

## Confirmed bugs and fixes

1. The all-clear code checked a supervisor owner named `combat`, but actual
   combat uses native attack leases. Record accepted offense in combat state
   and observe it without advancing actions. Kill confirmation and no-target
   cleanup retain the timestamp; old fights cannot affect a later alarm.
2. Send Home discarded the travel mode and selected vehicle while checking
   its displayed roster. Forward the complete selection, including in the
   Who selectors, so seated travellers are shown and counted consistently.
   Walking still excludes seated companions.
3. Road fallback changed the requested mode after its review key had been
   created, causing the first Send to be rejected. Retain the request and show
   the review's effective route; dispatch that reviewed fallback once.
4. Study selection remembered an outfit before an approach or inspection
   succeeded. Stage the group on the activity and commit it beside the body
   completion marker. Aborts, skeletons and crawler-specific openings do not
   create outfit memory.
5. Camp opinion ignored the cached human-threat lane. Recognized hostile
   humans now select the danger reply; protected bystanders do not.

## Verification

- A new hostile-human regression failed on the original code at its intended
  assertion, then passed after the fix.
- Normal/debug Lua compilation and the focused voice harness pass. The latter
  exercises 49,512 assertions over the existing 97 topics and 1,031 lines.
- The Home Trip UI harness passes with production-style request/review keys,
  all-seated and mixed crews, single/group selection, walking exclusions and
  first-click fallback departure.
- Gameplay adds actual combat update, equipment, approach, rejection, kill
  observation and cleanup cases, without fabricating a supervisor owner.
- Study tests cover aborted preparation, retry, successful completion,
  a distinct repeated outfit, save/reload, day rollover and special openings.
- Full gameplay, including the 21 voice mutation controls: passed.
- Final serial project gate: **30/30 passed**, exit 0, approximately 754
  seconds including a fresh reproducible bridge build. Core, source/installer,
  gameplay, navigation, storage, perception, combat barriers, UI, both NPC
  adapters, persona controls and both packages passed. The 21 voice mutation
  controls also passed against the final code.

Evidence: `C:/ZOMBOID/outputs/review-02695/`. No game was launched and no live
acceptance or local installation is claimed. Tests run serially with capped
Java resources.

## Wood-expedition follow-up

The 0.26.94 report stops at `wood_carry_capacity`, after a usable axe is found.
Native inventory weighting treats worn and hand-held bags as equipped, but
wood admission only counted worn bags. It now includes actual hand items and
rechecks the slot at pickup. Loadout now shows the Strength carrying limit,
matching wood admission, instead of the inventory's hard limit of 50.
Three cases were added to the existing wood harness for primary-held,
secondary-held and put-away bags; the held-bag case fails on the old worker.
The wood, wood-mission, wood-integration and main gameplay harnesses pass,
as does normal/debug compilation. These focused checks cover this follow-up;
the 30-stage gate above predates these two small changes. No live outcome in
the tester's save is claimed.

## Packing and departure preparation

Shared preparation now runs on each member's own decision path. It keeps
mission tools, preferred weapons, basic supplies and protected items, stores
unrelated stock at the originating camp, and packs useful loose items into
equipped bags. Camp supplies may fill ordinary shortages; missing food, water
or medical basics warn without blocking departure. Required tools and a
minimum viable cargo load still block. Scout trips reserve no cargo space.

Inventory assessment continues in slices of 80 items, with limits of 4,096
items and 128 containers; supply searches inspect up to 80 items per step.
Preparation has no background service. Travel, boarding, the departure line
and the turn-home clock wait for readiness. Full storage retains the exact
items, with a reduced-capacity departure when the minimum load still fits.
Outside camp, preparation only packs the carried kit. Blocked preparation
retries after three minutes and retains a manual retry.

Saves retain the pending preparation obligation and stable camp/member IDs.
Reload audits actual items again. Existing supervised transfers settle before
gear changes, cancellation or departure cleanup; completed moves stay done.
The bridge and save schemas are unchanged.

Filter masks, including improvised and filterless variants, are excluded from
automatic personal acquisition and clothing upgrades. A recruited companion
may remove an automatically worn mask during quiet upkeep. Manual Wear remains
available, favourites remain owned, filters and charge are untouched, and
independent characters' authored outfits are preserved.

Focused compilation, gameplay, wood, mission, Decision, integration and UI
checks pass. The integrated serial project gate passed **30/30**, exit 0,
in approximately 755 seconds, including source/installer, gameplay, UI,
adapters, persona controls and both packages. The rebuilt bridge is unchanged:
SHA256 `142325e87da9c8aa0a4e198d7d995493540f75305678b19fbfc06b71ae1b77c9`.
A final scan-limit wording correction was checked
by parsing the translation JSON. No live game run or installation is claimed.

## 0.26.96 release checks

Release metadata is synchronized across the canonical version, both mod.info
files, Lua identity, READMEs and bridge manifest. The rebuilt payload differs
from the fully tested bridge only in `META-INF/MANIFEST.MF`; every class file
is identical. Protocol `42.21-isocompanion-29` and save schemas remain unchanged.
The release-sync check and both Workshop and standalone package builds pass.
The 0.26.96 bridge SHA256 is
`ce2765782dd915dca4ef2e31e54fd8aeae120fa836a444742ab7b65d62eaa6b1`.
Evidence: `C:/ZOMBOID/outputs/review-02695/release-02696-*.log`.
