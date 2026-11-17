<!-- SPDX-License-Identifier: MIT -->

# Stay With Me

Living Fellows 0.27.31 recognises Stay With Me 0.6.5, Workshop item
[3800989007](https://steamcommunity.com/sharedfiles/filedetails/?id=3800989007),
mod ID `Bridge`. Enable both mods normally. No separate compatibility mod or
setting is needed. Support diagnostics include `stayWithMe` adapter status.

Stay With Me's companions and seated visuals are protected people to LF.
They are excluded from zombie threats, remain neutral even with competing
hostile NPC metadata, and cannot receive LF melee, firearm, shove or stomp
requests. LF's own native hit lists also remove these people before applying
damage, including incidental contacts when a companion attacks a nearby zombie.
Protection applies even when LF's general friendly-fire option is enabled.

The adapter reads current `NotAloneBody`, `notAloneBody`, `SWMSeatPuppet`,
the current client body, and Stay With Me's client/server identity APIs. It does
not identify NPCs by their name or appearance. Released unmarked bodies do not
keep LF immunity. Ordinary zombies remain enemies. Other attackers, including
the human player, retain their own native hit lists.

Stay With Me continues to own its AI and damage rules. LF neither changes its
navigation nor overrides zombie pathing. This is LF-side protection; it does
not promise reciprocal combat behaviour from unrelated mods. LF remains a
single-player mod.

The downloaded [author-published source](https://github.com/rdflwr13/stay-with-me)
was pinned at `8f93627cfa93d4a50c14d8ff2e9eb5b0326c4d25` (0.6.5). It is
used locally for contract tests and is not redistributed with LF.

Run the focused harness with the downloaded mod's `common` directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Test-StayWithMe.ps1 `
  -StayWithMeRoot '<Stay With Me>\Contents\mods\Bridge\common' -RequireSource
```

The harness executes the original client/server identity functions, LF
perception and relationships, all four direct attack handlers, native hit-list
filtering and reverted-fix controls. The full release gate also exercises the
filter with actual Build 42.22.2 zombie objects and a real Kahlua callback.
These are harness checks; no combined-mod live play session is claimed.
