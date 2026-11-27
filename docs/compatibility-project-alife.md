<!-- SPDX-License-Identifier: MIT -->

# Project A-Life compatibility

Living Fellows includes an optional adapter for [Project A-Life](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183). The [validation record](validation-project-alife.md) covers A-Life **1.4.6** on **Project Zomboid 42.21.0 single-player**. The adapter activates when both mods are enabled and it finds the required Interop v1 interfaces. Neither mod is installed or enabled automatically.

The Workshop published A-Life **1.5.4** for Build 42.22 on November 25, 2026. Its published Lua passes focused checks for perception, combat wounds, and defending another LF person. On 42.22.2, a live run confirmed A-Life wounds reaching the intended LF actor, and a cold reload restored both mods’ actors and the LF inventory. Reciprocal combat on 1.5.4 remains open. Support reports whether the running interfaces are ready. [Workshop change notes](https://steamcommunity.com/sharedfiles/filedetails/changelog/3803984183)

Companions, camp residents, households and Strange Folk can recognize A-Life people and participate in two-way combat. Friendly and neutral people are protected in firing lanes. LF keeps its combat orders, Hold Fire, wound treatment, retreat and household territory limits. Regular zombies remain a separate threat.

Companions and camp residents share your A-Life faction reputation. Independent LF people start neutral and keep their own reputation and retaliation. Self-defence uses A-Life's aggression records. LF people retain distinct identities throughout: sharing faction reputation does not share your player-slot identity or character lifecycle.

Each mod owns its own people, actions, inventories, corpses and saves. A-Life retains its attack timing, accuracy, armour, wound calculations and damage settings. The adapter does not add damage or replay a failed hit. Recruiting A-Life people, automated trading or robbery negotiations, and multiplayer are outside this profile.

Use **Options → Living Fellows → A-Life NPC compatibility** to turn combat integration off. Human classification and identity guards remain. **More → Support** reports readiness, missing interfaces or changed hooks. Running A-Life and Bandits together is not supported by this profile; use one external NPC mod at a time.

## Implementation boundaries

`SCALifeAdapter.lua` extends A-Life's perception-specific player provider, with a 250 ms membership cache and live native positions. It leaves the global player locator, simulation/spawn anchors, engine player lists, local-player flags, cameras and controllers alone. A companion already occupying LF's secondary view is included once.

LF aliases use `lf:<persistent LF UUID>` with a separate loaded-incarnation stamp. Lookups require the current living registered body. A-Life ownership checks require its current registry generation and exact Watchdog shell binding before granting combat authority. Incomplete shells stay outside ordinary zombie handling.

Faction reputation is delegated explicitly for party members. A-Life's player-state cleanup and notifications cannot treat an LF spawn, death or retirement as the main player's. Scoped wound guards verify the exact native body and immunity at application time. Rejection aborts the attack path so A-Life's emergency `AddDamage` fallback cannot bypass protection.

Wrappers chain existing functions and restore only their own bindings. World teardown retires retained callbacks. A bounded watchdog handles late initialization; replaced interfaces stop integration with a diagnostic rather than overwriting another mod's changes. No A-Life files or assets are packaged, and LF save schemas and bridge protocol are unchanged.

The [validation record](validation-project-alife.md) distinguishes automated checks from completed live scenarios. The household shooting blocker is resolved: native pistol hits now pass with the player outside sight of the fight, in both mod load orders. Full armour, window and protected-bystander scenarios remain open, and existing expedition driving-return failures remain a separate acceptance prerequisite.
