<!-- SPDX-License-Identifier: MIT -->

# Actor provider investigation matrix - Project Zomboid 42.20.4

| Candidate | Kahlua/loader result | Native components | Update result | Decision |
|---|---|---|---|---|
| ZombieBuddy-loaded `SCBridge` class | ZombieBuddy loads the declared JAR/package and exposes the owned bridge to Kahlua. Living Fellows pins ZombieBuddy 2.3.3+ and bridge protocol `42.20-isocompanion-4`. | Full native companion components | Supported single-player launch path with fail-closed health checks | Production provider |
| Stock `IsoSurvivor.new` / `SurvivorFactory` | Exposed to Kahlua | BodyDamage, Moodles, XP and emitter are null; HumanVisual access fails | Unsafe shell | Rejected |
| Custom `IsoLivingCharacter` | Requires unsupported custom class loading | Some components can be initialized | Native Moodles update casts to `IsoPlayer` | Rejected |
| javaagent-modified `IsoSurvivor` | Manual JVM argument and game-class instrumentation required | Prototype only | Spawn/update gate incomplete | Rejected; never packaged |
| Custom `IsoGameCharacter` subclass | Requires unsupported custom class loading and extensive initialization | Incomplete | No supported human update contract | Rejected |
| Stock `IsoPlayer.new(..., false)` + `setNpc(true)` | Constructor is exposed in actual Kahlua | BodyDamage, Moodles, XP, emitter and HumanVisual are non-null | Headless fixture reaches render-context work then stops because OpenGL is unavailable; in-game behavior unproven | Private experiment only, OFF by default |
| Custom `SCNativeCompanion extends IsoPlayer` | Loaded through ZombieBuddy for Workshop or the reversible local development launcher | Native BodyDamage, Moodles, XP, emitter, HumanVisual, inventory and pathfinding are present | Automated isolation tests and protected in-game sandbox checks preserve local-player ownership | Production actor; single-player only |

The real-JAR `IsoPlayer` control also proved `isLocalPlayer()==false` and no mutation of `IsoPlayer.getInstance()`, local slots `0..3`, `numPlayers`, or existing slot indices during construction. Live Lua observes those slots only through `getSpecificPlayer()` because `IsoPlayer.players` is a Java array that cannot be indexed as a Kahlua table. The candidate itself reports player number `0`, which remains a material risk. The headless OpenGL failure is classified as an incomplete fixture, not API acceptance.

Direct use of `setLocalPlayer(1000, actor)` was also rejected by the real JAR with an array-bounds failure: the local-player table has four entries. Slot assignment does not rewrite the candidate's internal player number.

The Workshop path is now explicit: ZombieBuddy 2.3.3 or newer loads the versioned Living Fellows JAR, and `SCActor.bridgeStatus()` rejects a missing loader, protocol mismatch, multiplayer, or failed readiness check. Runtime still fails closed and never substitutes the experimental raw `IsoPlayer` provider in public builds.
