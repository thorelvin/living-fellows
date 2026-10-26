<!-- SPDX-License-Identifier: MIT -->

# Bandits2 compatibility

Living Fellows includes an optional Lua adapter for the official
[Bandits2](https://steamcommunity.com/workshop/filedetails/?id=3268487204)
core on **Project Zomboid 42.21.0, single-player**. It activates when both
mods are enabled and the required interfaces are available. Bandits is an
optional dependency; Living Fellows does not install or enable it for you.

The adapter covers companions, camp residents, independent households and
Strange Folk. Hostile Bandits are human threats. Neutral or friendly Bandits
are protected from incidental fire, without becoming party members. LF keeps
its combat orders, retreat behavior, household pursuit limits and authored
character protections. Zombies remain a separate threat.

Bandits keeps its own hostility model, attack timing, accuracy, armor and
wound calculations. Attacking a Bandit can make its group hostile to the
player and LF characters through Bandits' existing witness and sync APIs.
Each mod keeps ownership of its actors, inventories, corpses and saves.
Recruiting or converting Bandits is outside this adapter's scope.

To turn off combat integration, use **Options → Living Fellows → Bandits NPC
compatibility**. Collision-safe identity guards remain while it is off, so
an LF companion occupying a temporary view slot cannot impersonate player 1.
**More → Support** reports activation state and missing interfaces.

Multiplayer, additional human split-screen players, Day One, Week One and
other Bandits overhauls require separate validation. The current live-test
results and remaining acceptance checks are in the
[validation record](validation-bandits2.md). In particular, driving expedition
return safety remains a separate open issue.

## Implementation boundary

`SCBanditsAdapter.lua` chains Bandits' public Lua functions. Its derived
player list is cached for 250 ms and invalidated by LF roster changes and
native slot membership changes. Entries retain live native positions.
The runtime checks interfaces once per second and retries late availability.
If another mod replaces a hooked function or its owning table, integration
stops with a Support diagnostic; it does not overwrite that mod's change.
Reset retires damage/list wrappers retained in other mods' call chains and
clears cached world references. Weak identity tombstones keep stale actor
references from becoming player ID 1. An old attack callback cannot apply a
wound in a new world.
Retained lookup hooks never send an LF alias to a default-player fallback.
Retained damage hooks delegate LF calls only within a fresh synchronous routing
scope for that exact victim and damage model.
Aliases use `lf:<persistent LF UUID>` and resolve only to the current living,
loaded, unprotected actor. Unknown, removed and dead aliases return nothing.

The engine player list, player count, local-player flags, cameras, controllers,
master-player selection and spawn ownership are unchanged. No shadow actors
are inserted in Bandits' caches. Damage routing exists only during the
synchronous stock damage callback, revalidates its exact victim and restores
the previous command binding after nested calls or errors. It adds no health
deductions and never replays a failed attack.
Malformed actor lists and non-finite wound values are rejected. Incomplete
Bandits brains remain protected humans until their current cache identity and
hostility fields are ready. Optional retaliation failures preserve the original
callback's return values and disable integration with a diagnostic.

No Bandits source or assets are packaged. Existing LF save schemas and the
native bridge protocol are unchanged; alias lookup is reconstructed after
load from LF's existing registry identities.
The accompanying bridge also supplies a non-local companion's own aim input
to 42.21's stock firearm callback and restores its temporary ballistic context.
Use the matching Lua/native build together. Full live combat acceptance remains
open in the validation record.
