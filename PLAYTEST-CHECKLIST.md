<!-- SPDX-License-Identifier: MIT -->

# Playtest checklist

## Mandatory gate before launch

- [ ] `scripts\Test-Project.ps1` passes against Project Zomboid 42.20.4.
- [ ] `VERSION.txt`, both `mod.info` files and the Support tab all report 0.22.7.
- [ ] Workshop-path testing has ZombieBuddy 2.3.3 or newer enabled before Living Fellows.
- [ ] The loose legacy `zombie\characters\IsoSurvivor.class` is absent and the game is closed.
- [ ] The local install displays `PRIVATE-NATIVE-BRIDGE.txt`.
- [ ] `ProjectZomboid64.json` uses `survivorcompanion/bridge/SCLauncher` and retains the original JSON backup.

## Provider invariants

- [ ] Candidate is NPC and `isLocalPlayer()==false`.
- [ ] Local singleton, player slots, `numPlayers`, split-screen indices, input and network state remain unchanged.
- [ ] BodyDamage, Moodles, XP, emitter, inventory and HumanVisual remain non-null.
- [ ] Ten actors update for 30 minutes without render/input/audio exceptions or static-player mutation.
- [ ] Zombies target actors normally; actors never receive local-player input or UI ownership.
- [ ] Spawn one zombie beside a passive companion: the zombie can acquire and attack the companion before the companion hits it, while a materially closer player remains the preferred target.
- [ ] Native damage, death, corpse, Knox death and zombie reanimation behave normally.
- [ ] A four-seat car assigns exactly three of ten companions to unique passenger seats; seven wait without teleport, damage, retry spam, or roster loss.
- [ ] Native and virtual vehicle boarding/exiting preserve correct actors and seats.
- [ ] `Ride with player` defaults on for old saves; followers approach assigned passenger doors, leave when the player leaves, and never attempt to board when it is off.
- [ ] Disabling Ride in a moving vehicle reports `Waiting for safe exit`; exit occurs only after a safe stop, and `Exit vehicle now` is visible only when seated and stationary.

## AI performance and scalability

- [ ] Repeat follow, combat, scavenging and loaded-household play with 1, 4, 8 and 16 active companions.
- [ ] Debug > AI performance profiler reports frame last/p95/max, load level, over-budget/deferred frames, yielded jobs and cache hits/misses.
- [ ] Refresh updates the profiler only when pressed; dragging the scrollbar is never interrupted by profiler redraws.
- [ ] Copy AI performance report includes the most expensive systems and companions; Reset clears accumulated samples.
- [ ] Ordinary play keeps mod frame p95 close to the configured 2 ms budget and does not produce repeated long spikes.
- [ ] Sustained artificial load raises the load level and extends normal/background intervals while combat, retreat, health and vehicle safety retain their cadence.
- [ ] A perception sweep, long route search, scavenging scan/score and production faction-house search each yield and later complete without restarting their frontier.
- [ ] Multiple companions share global perception, navigation, scavenging and faction-search quotas without starvation or duplicate work.

## Product behavior

- [ ] Spot one zombie, two, three-to-four, five-to-eight, and nine or more at safe distance; the overhead report matches the contact scale and does not repeat the same wording while alternatives remain.
- [ ] Under quiet/Stealth behavior, distant contact uses a readable `*hand signal*` overhead emote and creates no world sound; urgent spoken warnings still create sound.

- [ ] Fresh and unrelated-data saves load without altering unknown data or actors.
- [ ] Five save/load cycles create no duplicate UUIDs or actors.
- [ ] A schema-1 save migrates once; a schema-2 companion retains nested bag hierarchy, worn and attached gear, both hand slots, weapon parts, fluid mixtures, condition and bounded item mod-data.
- [ ] Force one incomplete inventory capture in a disposable test: the previous stable document remains intact and the next healthy save succeeds.
- [ ] Lower Max companions or Max households below the current population, reload, and verify no existing companion or household is deleted; only future spawning is capped.
- [ ] Change encounter cadence, companion needs rate and UI opacity in Sandbox settings and verify each effective value after reload.
- [ ] Follow/stay/guard/regroup/retreat work across distance, floors, doors, windows and obstacles.
- [ ] Movement defaults to `Copy player` for a new recruit and for an old recruited save without the movement-policy marker.
- [ ] In ordinary Follow, crouching, walking and running are mirrored without rapid pose resets; while holding formation, the companion remains crouched when the player remains crouched.
- [ ] Catch-up and immediate combat may override Copy player; retreat and true overrun always request native running on clear ground, then return to copied movement after the urgent condition clears.
- [ ] During escape, doors, fences, stairs, windows and unavoidable vegetation walk only for their constrained transition; running resumes on the next clear edge.
- [ ] Doors/open leaves, locked or obstructed gates, cars/trailers, moved furniture, full-square thumpables, narrow gaps, stairs/slopes, crowds and safehouse boundaries cannot trap a follower on a repeatedly selected edge.
- [ ] While native routing is still pending or turning at an obstacle, the companion waits without restarting the request, sliding, or reporting a false stuck recovery.
- [ ] Two companions approaching a door, fence or stair reserve the whole short choke in order; the second waits outside and proceeds after the first clears it.
- [ ] Four or more companions approaching the same door remain in a stable priority/FIFO queue; no later ordinary request steals an occupied corridor, and its lease remains owned throughout a slow native transition.
- [ ] Put two companions head-to-head in a narrow aisle: the deterministic lower-priority actor receives a yield request and sidesteps when possible; if neither side is free, bounded deadlock recovery eventually clears the aisle without both actors switching sides every frame.
- [ ] Approach the same sink, container, patient and construction target from blocked sides; the companion chooses another reachable interaction position without circling or retrying the enclosed side.
- [ ] After a route succeeds, repeat it once and confirm it remains preferred; physically block that edge and confirm the temporary failure memory selects a different route until the object state changes or the memory expires.
- [ ] Trees and bushes are avoided when a clear route exists but remain usable under native steering when they are the only escape.
- [ ] `navigation-blocker` logs identify blocker type, object, square, actor state and recovery; failed static edges remain temporarily blacklisted while moving crowds clear sooner.
- [ ] Knockdown, climbing and unfinished-action states wait for the native state instead of issuing competing movement; stale wall-collision ownership is cancelled, and a state that never clears reports bounded `actor_state_timeout` rather than waiting forever.
- [ ] Open, locked, barricaded, invincible, smashed/glass, smashed/clear, thumpable and empty-frame windows each use the correct safe behavior.
- [ ] At a blind 90-degree corner the follower checks once, slows, and sidesteps while facing the concealed route; it does not take the tight turn blind.
- [ ] Two companions keep separation on stairs, inspect a blind landing once per stair sequence, and do not deadlock in the choke.
- [ ] After entering and looping through a building, retreat selects a verified nearby exterior route or the loop-erased entry trail; no repeated route-search stutter occurs.
- [ ] On safe flat ground, break contact uses backward/diagonal/lateral player footwork while facing the threat; it turns normally at a blind corner, door, window, stair, tree, bush, close grab, or encirclement.
- [ ] If a cuttable bush is the only usable house exit, urgent retreat walks through it with native steering and resumes tactical movement only after clearing it.
- [ ] A safe retreat can alternate one shove or clear-lane covering shot with movement; hold fire, Stealth, encirclement, unsafe range, or friendly-fire risk prevents that shot.
- [ ] Melee, firearm, reload, shove, stomp, kite, retreat, hold-fire and friendly-fire rejection are exercised.
- [ ] Shove one isolated zombie onto the floor: the companion stomps that same zombie when close enough. Add a second immediate attacker, move the target away, or let it remain standing and confirm the stomp is abandoned.
- [ ] Compare a rested, calm skilled fighter with a panicked, exhausted, overloaded novice using a heavy damaged weapon: the second survivor disengages earlier and preserves a visibly larger endurance reserve.
- [ ] Place equal-distance zombies in front, beside and behind a companion: the companion turns on the rear/flank danger first; two companions distribute across unclaimed targets instead of repeatedly dogpiling one zombie.
- [ ] A safe firearm user raises the weapon and settles before firing. High Aiming skill shortens the pause, panic/stress lengthen it, and an immediate close threat cancels the wait in favor of defense or escape.
- [ ] The team Rules of Engagement selector applies Stealth, Close Defense, Ranged Support, or Weapons Free to all current and later recruits.
- [ ] Main order, follow distance, work mode, movement, combat stance, weapon priority and group use one selector each; scavenging, overload, hold fire and Ride use one checkbox each.
- [ ] Defensive stance and Quiet weapon priority are selectable, persist independently, and do not silently rewrite the team Rules of Engagement.
- [ ] Passenger firearms require Ranged Support or Weapons Free, an open/broken side window, safe speed, ammunition, range, sight, cadence, and a clear friendly-fire lane.
- [ ] Three-sided close pressure forces a sustained break-contact response even in aggressive mode; distant targeting zombies alone do not trigger a false overrun.
- [ ] Rescue, kneeling treatment, ripped emergency bandage, downed recovery and native bleeding are exercised.
- [ ] Scavenging ignores player-opened containers and prevents dual reservation.
- [ ] A companion equips a better backpack, packs role gear into it, and still finds/uses items stored inside nested bags.
- [ ] With combat clear, a companion takes and equips only a materially better garment from a zombie corpse; danger interrupts corpse looting.
- [ ] Safe idle near a clean sink or well washes visible body dirt/blood and then dirty clothing, bags or equipment while consuming water.
- [ ] `Allow overload` is off by default, changes only the selected companion, survives save/load, and visibly changes that companion's load policy.
- [ ] Hunger and thirst rise at half speed at 1x and accelerated time; eating and drinking retain vanilla item/moodle effects.
- [ ] Hungry/thirsty companions use safe carried supplies, then player-opened camp storage, then nearby clean sinks/wells; they reject rotten, poisonous, dangerous-raw and tainted supplies.
- [ ] Two companions cannot take the same camp item, and an interrupted/reloaded supply run neither duplicates nor deletes it.
- [ ] A build order fetches a hammer, plank and two nails from visited storage, waits safely if another worker owns the container, and reports genuinely missing supplies.
- [ ] Distant visible danger uses a silent hand signal; immediate/player danger uses one rate-limited audible warning.
- [ ] Reading, repair, bandage replacement, supply crafting and seating cancel on danger/orders.
- [ ] Bandaging, emergency cloth tearing, scavenging, clothing changes and camp work apply no result before their full animation completes; interruption leaves each item and wound in exactly one valid pre-action state.
- [ ] During Loot, Bandage, Craft, sitting, climbing and one unrelated vanilla timed action, ordinary Follow never changes the actor's pose or position. Retreat/combat may interrupt only through the owned rollback contract, then returns to a clean locomotion state.
- [ ] In the private Debug tab, select a moving companion and refresh Movement recorder: state, owner, action, requested/effective speed, override, target, next square, native path, queue, blocker and recovery are coherent. Copy produces only the selected companion's last 30 seconds; Clear removes its history without affecting movement.
- [ ] After safe successful work, companions sometimes pause briefly or look around without requesting another path; danger, bleeding, a new order, vehicle movement or a departing followed player cancels the pause immediately.
- [ ] During safe Stealth downtime indoors, a companion occasionally reserves an open curtain in the same building, sneaks to it, and closes it only after arriving; it never reopens one while Stealth remains active.
- [ ] Ordinary daytime companions only rarely open/close curtains, nighttime favors closing, multiple companions do not crowd or flip the same curtain, and danger/new orders cancel the approach immediately.
- [ ] Inventory, health, conversations, groups, context commands and roster controls work.
- [ ] Ask Status, Needs, Opinion, Relationship, Encourage and Plans repeatedly; the same companion avoids its recent lines while answers remain factually consistent.
- [ ] Compare brave, cautious, caring and practical companions in the same situation; phrasing varies without changing the command, need or safety decision.
- [ ] Trigger repeated zombie warnings, work failures, supply requests, stress, joy and grief; line pools vary, names remain correct, and no speech appears over the player.
- [ ] Time a short and a long overhead line at normal and accelerated game speed: each stays fully readable over its companion for its 8-15-second length target before fading, creates no duplicate rows, and yields immediately when a different line is spoken.
- [ ] Stop outdoors with a nearby companion on Follow: it remains alert/standing and never starts reading, crafting, washing or sitting. Repeat indoors, let downtime begin, then walk away; the NPC cancels the pose before following and never moonwalks, slides or retains a kneel. In Debug, confirm `[SurvivorCompanion][downtime]` names each start/finish/cancel kind.
- [ ] Opening Orders, Gear and Groups creates every selector without a Lua error; changing each selector applies once and shows feedback.
- [ ] Holding and dragging either roster or detail scrollbar for at least five seconds is uninterrupted by scheduled UI refreshes; the view catches up after release without jumping.
- [ ] A Debug household spawn reports its house coordinates, direction and distance, and creates a visible yellow house marker plus HUD direction arrow; Locate and Clear work for every listed household.
- [ ] Support reports Ready with the expected bridge protocol, copies a bounded report to the clipboard, explains a deliberately missing/outdated bridge, and retries a tripped test subsystem without restarting the save.
- [ ] Two discovered households show one persistent Faction World relation; forced warning, trade, aid and dispute events update bounded news and survive save/reload.
- [ ] Helping or harming one known household causes only a small relation-weighted word-of-mouth standing change in another known household; unknown groups remain hidden and no off-screen event kills actors or damages a base.
- [ ] A trusted household with the required completed contracts nominates a nonessential resident; an ineligible, hostile, offended, or one-survivor household explains why recruitment is unavailable.
- [ ] Starting a trial moves the same actor, identity, equipment and nested inventory into the recruited roster without cloning it; save/reload preserves the trial and its deadline.
- [ ] Trial extension, return home, permanent join and death each produce the correct persistent household consequence; a failed transfer rolls both faction and roster state back.
- [ ] The minimap shows a moving red dot and first-name label for every living recruited companion, including a trial follower, and shows none for neutral encounters, dead actors, or unrecruited household residents.
- [ ] A recruited death creates one named grief record per living teammate; repeating the terminal update does not duplicate the memory or mood penalty.
- [ ] A nearby witness or close friend grieves more intensely than a new distant teammate; Overview, Journal and How are you? all name the deceased.
- [ ] Mourning begins only in safety, may use a quiet standing or ground-sitting response, and is interrupted immediately by zombies, injury or a survival order.
- [ ] Save/reload preserves acute grief and its pending response; after sufficient game days the mood penalty decays while the named death memory remains.
- [ ] A household mourning a dead resident reports the loss in status conversation, retains a watch, and uses only bounded off-watch mourning routines.
- [ ] Classified camp stores report loaded stock against resident-scaled targets; unloaded stores are explicitly marked unknown instead of counted as empty.
- [ ] Rotating, role-based and all-hands watch policies select the expected residents, while workload, routine and automatic-maintenance policies survive save/reload.
- [ ] Safe on-duty residents without a job read, sit, wash or perform another valid downtime activity; automatic sort, repair and craft jobs are never queued without a real actionable item and capable worker.
- [ ] Each recruited companion's context submenu is grouped into Talk, Orders, Target actions and Companion; no submenu becomes taller than the screen.
- [ ] Remove this barricade approaches the player-selected side, uses a pry tool or fueled blowtorch, removes every plank/metal section through native actions, recovers materials, and resumes the prior order.
- [ ] Dismantle this object appears only for dismantlable thumpables, requires an unbroken saw and screwdriver, drops vanilla recovered materials, and resumes the prior order.
- [ ] Save/load during either destructive target order preserves the object, work kind and selected barricade side without duplicating the action.
- [ ] UI fits 1280x720, 1920x1080 and 2560x1440 with long names and large fonts.
- [ ] On both docks, one Collapse click hides the full panel and leaves exactly one LF launcher without reopening; LF and F7 restore the saved full panel, launcher dragging/resolution changes stay on-screen, and reload while collapsed creates no duplicate or partial panel.
- [ ] Save while collapsed, quit completely, and reload: the LF launcher is drawn as soon as gameplay starts, before any F7 input.
- [ ] Enable scavenging and watch a companion approach containers and corpses from several tiles away: the approach path stops completely before Loot begins, the full rummage animation finishes, the item transfers once, and only then may pathing resume.
- [ ] With a worn backpack, Overview and the roster name the approached/looted item, then report the exact verified pickup destination; the source loses that same object and the backpack gains it.
- [ ] Danger, a new order, selected-item removal, full load, and quit/reload before Loot completion each preserve exactly one item location and never commit late.
- [ ] Two companions cannot own one container simultaneously; unchanged unhelpful containers are not repeatedly searched, while changed contents become eligible immediately.
- [ ] After native recovery or controlled relocation, the companion remains a fully rendered human rather than a moving shadow, does not resume an old path, and completes the left/right room-entry sweep through a normal doorway.
- [ ] Packing, base-storage deposit, ground drop, camp-supply retrieval and build-supply retrieval mutate inventory only after their complete Loot animation.
- [ ] One, four and eight actors stay within the target frame-time regression and show no sustained stutter.

Record the game build, sandbox settings, save cycle, diagnostic log excerpts and any invariant rollback reason for every run.
