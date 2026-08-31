Living Fellows: Companion 0.22.8 reliability playtest candidate

The included native bridge supplies SCNativeCompanion, an original IsoPlayer
subclass that remains outside the local-player slots. Workshop installations
require ZombieBuddy 2.3.3 or newer. The local development installer can instead
add a reversible bridge launcher to ProjectZomboid64.json for isolated tests.

Single-player only. Split-screen and multiplayer fail closed. If the bridge is
missing, outdated, or fails its isolation checks, companion spawning is disabled
without substituting a zombie or an unguarded IsoPlayer.

The persistent roster supports up to sixteen companions. Orders include follow,
stay, base guard/patrol, scavenging, useful chores, varied idle activities,
and supply crafting. The roster opens automatically once after the visibility
update; F7 collapses or reopens it and is configurable under Living Fellows in
the keybinding options. Hunger and thirst advance at half speed. Companions use
real food/water actions, visited camp storage, and nearby clean water sources.
Right-click a barricadeable door or window to order a selected companion to
fetch a hammer + plank + two nails from visited storage and barricade it.
The recruited-companion context menu is grouped into Talk, Orders, Target
actions and Companion. Target actions can also remove every plank from the
selected side of a barricade with an appropriate pry tool (or a fueled
blowtorch for metal), or dismantle a player-built object with an unbroken saw
and screwdriver. These use the game's native timed actions and recovered items.
After a one-shot job the companion returns to the previous role. Work targets
are exclusive and save/load-safe. Zombie danger interrupts work, weighs nearby
healthy teammate support, and produces a silent hand signal or urgent shared
warning according to context. Companion death is final;
the game remains responsible for the corpse and possible reanimation.

Companions now have deterministic personal backgrounds and persistent trust,
bond, morale, stress, time-together, care history, and semantic memories. Their
answers reflect real wounds, hunger, thirst, supplies, mood, recent treatment,
shared escapes, rescues, and useful work. Background details open gradually as
trust grows; reassurance and praise are contextual and cooldown/achievement
gated. The roster and right-click conversation menu expose the new topics.
Validated Build 42 player hand signs cover follow, hold, regroup, cautious
follow, move out, fire discipline, and fallback, with visible NPC acknowledgement.
Six safe human companion emotes are also available from the roster.

Safe downtime now includes a bounded curtain habit. A companion may reserve a
curtain in the same building, walk to it, and toggle it after arriving. Stealth
companions prefer closing open curtains and never reopen them; ordinary daytime
behavior may rarely open or close one, and nighttime favors closing. Danger or
a new order cancels the task, while reservations and cooldowns prevent crowding
or repeated curtain flipping.

0.13.1 adds bounded personality preferences, one optional personal objective,
one persistent low-value keepsake, a "plans" conversation, and a sixth read-only
Journal tab. The Journal never reveals private state by opening it. Keepsakes
remain movable by the player, survive root/nested-carried save cases, and are
protected from companion automation that would consume or craft with them.
Existing 0.13.0 SC_SaveV1 companions normalize additively. This candidate has
passed headless gates but still requires the native in-game acceptance test.

0.14.2 adds a persistent camp layer with drawn zones, classified storage,
resident roles, leased work queues, sorting, medical chores, maintenance and
native construction. The seventh Base tab reports camp work and infection
crises. Bites now spread knowledge through witnesses, symptoms, confession or
medical checks. Companions react differently and can watch, quarantine, exile,
leave notes, preserve keepsakes, or propose a mercy killing. Irreversible
outcomes require a safety delay plus a separate explicit confirmation and use
a real armed native action before vanilla BodyDamage applies death.

Native companion construction now runs only after the requesting Lua frame has
unwound, preventing the Build 42 ReturnValues pool failure that could disable
ordinary inventory timed actions. A rejected optional keepsake is deferred
instead of rolling back an otherwise healthy companion.

0.14.3 keeps the IsoPlayer body and components but bypasses its local-player
controller during companion updates. Generic character physics, wounds, timed
actions, state machines and animation still update, while OnPlayerUpdate,
player input, camera ownership and the player singleton remain local-player
only. Speech also rejects non-companion actors, and Java calls preserve explicit
nil arguments required by Build 42 navigation APIs.

0.14.4 isolates native companion construction from OnCreateLivingCharacter
callbacks and restores the exact callback sequence immediately afterward.
Recruited companions that lose an unloaded world square are reattached on a
safe loaded square near the player; unloaded neutral encounters retire quietly
instead of producing a repeating health-gate error.

0.14.5 fixes the observed ReturnValues cascade caused by calling Build 42's
InventoryItem.hasTag overload with a Lua string. Inventory scans now iterate
ItemTag objects and compare their stable names, avoiding the engine overload
failure that could poison later hotbar, timed-action and inventory calls.

0.14.6 adds stable travel-relative follow slots, personal-space and right-of-way
reservations, separate formation arrival/release bands, and interruptible
conversation positioning. A companion now settles 1.2-2.8 tiles from the
player, faces them, and performs one validated human gesture. Danger pre-empts
social movement, and no positioning action is ever applied to the local player.

0.14.7 adds periodic rear checks while holding formation and restores the
established travel-facing direction afterward. Room entry now pauses at the
threshold and checks both sides from the approach heading. Longer follow and
regroup paths compare up to three bounded alternatives for traversal cost,
nearby threats, crowding, and excessive turns. Urgent survival movement skips
these deliberate checks.

0.14.8 adds recursive bag awareness, automatic wearable-bag packing, safe
zombie-clothing upgrades, and body/equipment washing at nearby clean water.
The Gear tab now has a persistent per-companion overload policy; it remains
off by default and stays bounded when enabled.

0.14.9 gives every companion a persistent vanilla Build 42 profession and a
compatible background trait. These provide grounded starting skills and small
preferences for personality, tactics, scavenging, downtime, personal goals,
inventory role, and camp work. Profession-specific history is revealed through
conversation, while the Overview and Journal show the public profession, trait,
and natural camp role. Existing records normalize deterministically.

0.15.0 adds bounded community autonomy. Survivors keep meaningful thoughts and
shared memories, grow bored without purpose, ask about supply runs, and receive
temporary boosts from sustained good morale. Their stable stress response can
be venting, purposeful pacing, withdrawal, an argument, a safe physical
outburst, or a depressive shutdown in which they seek a quiet room and sit on
the floor. Danger always interrupts these episodes. Player reassurance shortens
a shutdown, and the roster shows current thoughts and actionable requests.

0.15.1 validates the complete companion action-animation allowlist against the
installed Build 42 player graph. Bandage, craft, and read use the exact native
enum values; loot, clothing, washing, variables, events, hand models, and emotes
match their vanilla actions. Paths retain an active native target, avoid stale
manual/path ownership, and prefer open ground over bushes and trees. Armed
companions ready their weapon when visibility is poor outside a threat-free
base, including blind corners, room entries, vegetation, darkness, and stairs.

0.15.2 makes container looting transactional. Companions reserve one target,
finish the native rummage animation, then commit exactly one verified transfer;
failed targets cool down instead of being checked continuously. Active visual
actions now own the pose, preventing movement while kneeling. All menu-button
labels are width-clamped, the carry-policy labels are shorter and clearer, and
scavenging is represented by one stateful checkbox instead of two buttons.
The world right-click Companion commands list is restricted to authoritative
recruited team records; neutral encounters remain recruitable from the roster.

0.15.3 keeps an owned door open until the companion has physically cleared its
threshold and makes stuck recovery sidestep the door plane before retrying the
route. Native Clothing identity now outranks filename fragments, so bulletproof
vests are equipped as armor instead of being classified as bullets and packed.
Conflicting wearable replacement is transactional and rolls back on failure.

0.15.4 treats tree squares as hard occupancy and adds clearance around roadside
trunks. Short tree-adjacent movement uses native capsule pathing, invalidates a
stale route after a local detour, and shifts a formation slot off a tree. A
stalled follower stops sooner, steps away from the trunk, and then repaths.

0.15.5 replaces Build 42's nonfunctional getBestSeat stub with explicit
passenger-seat scanning and real door-distance checks. Companions approach a
free passenger door and board only while the vehicle is nearly stationary;
path movement is suspended while seated. Verified passengers are no longer
mistaken for unloaded actors merely because they have no ordinary world square.
A follower who misses the car stays in the roster and is recovered only after
the player exits, while native exit places riders safely beside their door.

0.15.6 adds a capacity-aware manifest for large teams. A four-seat vehicle
assigns three unique non-driver seats; excess followers wait safely without
teleporting, taking damage, or leaving the roster. One team-wide Rules of
Engagement selector controls Stealth, Close Defense, Ranged Support, or Weapons
Free and is inherited by later recruits. Firearm-equipped passengers may shoot
only in the two ranged doctrines, through an open or broken side window, below
the doctrine speed limit, and after range, sight, cadence, retreat, and friendly-
fire checks pass.

0.15.7 adds real backward, diagonal, and lateral player locomotion while a
retreating companion watches a visible threat. Tactical strafe is allowed only
on clear flat ground; doors, windows, stairs, trees, bushes, blind turns, close
grabs, and encirclement make the companion turn and escape normally. If a
cuttable bush is the necessary way out, the urgent route remains valid and the
actor walks that edge under native collision steering. A safe retreat may
alternate one shove or friendly-fire-checked covering shot with movement.

Indoor movement now checks blind corners and stair landings, preserves spacing
in stair chokes, and sidesteps while watching the unseen route. Companions keep
a bounded memory of their entry path and nearest verified outdoor exit. Close
threats are counted by direction, so a surrounded companion breaks contact and
uses that route instead of fighting until grabbed.

0.16.0 adds persistent autonomous survivor factions, beginning with one-to-three
person barricaded households. Residents occupy eligible houses, use native timed
barricade actions, warn and defend against trespassers, keep real shortages and
reserved rewards, and unlock conditional barter after a completed request.
Nonlethal hostility supports delayed, value-checked restitution; murder remains
permanent. Faction actors never enter the recruitable companion roster. The
private build exposes manual faction spawning and state controls in a debug-only
tab; release builds retain bounded production spawning and hide those controls.

0.17.0 adds persistent household personalities and internal relationships,
visible half-hour routines, inventory-based supply scarcity, and one entrance
representative for acceptable visitors. Rare supply, illness, and dispute crises
change household behavior without outranking danger. Tolerated or trusted groups
can share imperfect rumors as real `[LF]` annotations on the vanilla world map.
The Factions panel exposes this state, while the private Debug tab can select all
profiles, trigger or resolve every crisis, advance routines, audit supplies, and
reveal rumors. All player-facing text remains English.

0.18.0 adds persistent household social contracts. Entrance representatives
answer contextual questions about needs, residents, trade, danger, rumors, and
access. A household keeps at most one supply, medical, or local-threat promise
active and remembers help, trade, threats, theft, withdrawal, and expiry.
Standing, personality, scarcity, crises, and favor affect invitations, reserve
refusals, markup, and explicit counteroffers. Hidden severity, diverted goods,
rival objections, unpaid rewards, and private dissent add bounded uncertainty.
Success may grant temporary guest access, safe rest, improved trade, more useful
but still imperfect rumors, and future recruitment consideration; the first
agreement never recruits a resident directly. The private Debug tab exposes all
contract types, complications, access states, completion, and expiry.

0.18.1 adds unique contract map markers, live inventory and threat progress,
bounded deadline and progress notifications, and real alternative medical goods.
Threat reports require a meaningfully loaded area. Promise withdrawal requires
confirmation; trade reserves explain both quantities and refusal reasons; access
and safe-rest readiness are distinct. Patient and household death close affected
contracts without incorrectly blaming the player. All state remains bounded and
save/load-safe.

0.19.0 introduces transactional save schema 2 for complete recursive companion
inventories, nested bags, equipment, attachments, weapon parts, fluids, and
bounded item state. Existing schema-1 saves migrate in place, while a failed
capture retains the previous known-good snapshot. Runtime subsystem failures
now recover through half-open circuit breakers. Sandbox options control encounter
cadence, companion limits and needs, household spawning, and UI opacity without
pruning existing saves. An always-visible Support tab reports native bridge and
runtime health, copies a bounded support report, and retries failed subsystems.

0.21.0 turns earned household trust into an explicit recruitment path. A trusted
household with completed contracts may nominate a nonessential resident for a
time-limited trial. The same persistent actor, identity, equipment and inventory
joins the companion roster; no replacement actor is spawned. At the end of the
trial the resident may join permanently, ask for more time, or return home, and
the household remembers the result. Death during a trial is permanent. Every
transfer is transactional and save/load-safe. Living recruited companions also
appear on the minimap like multiplayer teammates, with a red position dot and
their first name; neutral encounters and faction residents never appear there.

0.21.1 makes permanent death matter socially. Every living recruited teammate
receives one relationship-weighted grief record when a companion dies. Witnesses
and close friends suffer more acute stress and lost morale; the effect decays
over several game days, but the named relationship memory remains. Once safe, a
grieving survivor may speak about the dead, seek a quiet place, sit or stand in
silence, and then return to duty. Danger interrupts mourning immediately. The
Overview, Journal and "How are you?" response expose the loss. Survivor
households also remember dead residents, mention them in conversation, and use
bounded mourning routines without abandoning their watch.

0.21.3 prevents a following companion from starting calm downtime outdoors.
Switching from downtime to follow now cancels and releases the owned visual
action before movement begins. Any vanilla or third-party timed action, such as
ISUnequipAction, blocks translation until its native queue and action pose are
clear. Debug builds log the exact downtime kind at start, finish and cancel.

0.21.4 makes Collapse a deterministic two-element transition. The expanded
companion window is hidden instead of being resized under the active mouse
event, and a separate edge launcher is shown. The launcher opens only after its
own mouse-down, so the Collapse button's release cannot click through and reopen
the menu. F7 and the LF launcher restore the saved expanded size and dock.

0.21.5 restores the saved launcher after Build 42 completes its in-game UI
startup. Menu construction no longer races the early OnCreatePlayer UI reset;
OnGameStart performs the final visibility transition, so a save that starts
collapsed immediately displays its LF launcher without requiring an F7 cycle.

0.21.6 gives interaction animations exclusive movement ownership. Before Loot,
Bandage, Craft, Read, Wear Clothing, Wash, or another verified visual action is
queued, the companion cancels its retained PathFindBehavior2 route and clears
bridge movement, running, sneaking, aiming, and strafe state. The engine can no
longer take one final approach step and trigger the action's stop-on-walk rule.

0.21.7 makes scavenging a verified select/reserve/approach/settle/animate/
commit/verify/resume transaction. Inventory changes only after Loot completes,
destination rejection rolls the exact item back, unchanged containers are
remembered, useful supplies prefer worn bags, and the roster/Overview show the
current task and last verified pickup. Commands, danger, capacity changes,
source removal and reset cancel safely. Packing, deposits, drops and camp/base
storage retrieval now use the same animation-before-effect ownership rule.
Native recovery also preserves the renderer slot while rebuilding world/square
membership, cancels stale pathfinder ownership, and repairs the Build 42.20.4
pending-removal flag when needed. Real-time helpers normalize the engine's boxed
timestamp value before arithmetic.

0.22.0 keeps AI work inside a measured two-millisecond frame budget. Combat,
retreat, health and vehicle safety run in the critical lane; background work
slows automatically when the profiler detects sustained overload. Perception,
route search, scavenging discovery/scoring and production faction-house search
now retain their frontier and continue over later frames. A short-lived shared
perception cache avoids duplicate nearby square reads. The debug-only tab shows
frame and subsystem p50/p95/max timings, yielded work, load level and expensive
companions, with explicit refresh, reset and copy-report controls. Automated
scale coverage exercises 1, 4, 8 and 16 companions.

0.22.1 makes native actions interruption-safe. Bandaging, emergency cloth
tearing, scavenging, equipment changes, downtime and camp work commit their
gameplay result only after the complete verified player animation. An
interruption rolls reserved inventory back instead of applying a late effect.
After successful work, companions may pause briefly to think or look around;
danger, bleeding, retreat, vehicle transitions, new orders and a separating
leader cancel the pause immediately. Movement now defaults to Copy player for
new recruits and migrates old recruited saves once. It mirrors crouch, walk and
run during ordinary following and while holding position, without repeatedly
resetting the crouch pose. Tactical safety and catch-up can still override it.

0.22.2 connects the bounded planner to Build 42's native path telemetry and
nearest-of-many routing. Native path ownership survives asynchronous path
starts, obstacle turns and animation-owned transitions. Doors, fences, stairs,
vegetation escapes and narrow corridors use continuous engine steering, while
companions reserve multi-node choke corridors instead of crowding one tile.
Short-lived, object-state-aware route memory distinguishes successful and
failed edges, and recovery adapts to geometry, vehicles, vegetation, crowds,
stairs and actor states. Container, water, medical, storage and building work
offers multiple interaction positions so the engine can choose a reachable
side. A companion may follow a successful shove with a stomp only while the
same zombie is grounded, close, and no second immediate threat makes it unsafe.

0.22.3 hardens group locomotion. Step and multi-node choke ownership is
non-preemptive, priority-aware and first-waiting-first-served. A companion with
right of way explicitly asks a lower-priority actor to sidestep, while bounded
deadlock recovery still makes clearance when neither can move. Native path
leases retain a corridor throughout door, fence and stair transitions. A
central Idle/Turn/Walk/Run/Strafe/Interact/Recover state machine guards every
actor dispatch, stops stale locomotion before owned or unfamiliar native
actions, and preserves survival-critical rollback. Private debug builds add a
bounded 30-second selected-companion movement recorder with target, next square,
owner, path state, queues, blocker, recovery and transition history. The Debug
tab can refresh, clear or copy its report; public builds do not record events.

0.22.4 makes survival escape authoritative over ordinary movement policy.
Retreat, overrun, neutral flight and hostile break-contact requests resolve to
native running at the final actor boundary even when Copy player, Walk, Sneak,
formation or weapon-ready routing requested a slower mode. Door, fence, stair,
window and unavoidable vegetation transitions retain safe walking, while a
controlled visible fighting withdrawal may still use player backstep/strafe
footwork; a true overrun turns and runs. Native animation blockers now have
bounded diagnostics, stale wall-collision ownership is cancelled, and an actor
state that never clears reports an explicit timeout instead of pretending to
make progress forever. Directionless retreat and cover fallbacks were replaced
with a concrete escape square or a verified vector away from the nearest threat.

0.22.5 adds event-driven combat barks for engaging, survival-critical retreat,
a prolonged fight against the same target, and a recently attacked target's
confirmed death. Each event uses varied English lines shaped by personality and
stress. Per-actor, squad-wide and per-event cooldowns prevent overlapping text,
choruses and tick-by-tick repetition. Ordinary combat speech stays quiet under
Stealth doctrine, but an overrun survivor may still yell a warning. These yells
create a modest real world-sound event and may alert nearby zombies.

0.22.6 makes contact reports situational. Companions distinguish one zombie,
a pair, a small group of three or four, a larger crowd, and a horde. Every
scale has a broad English line pool plus personality and stress variants.
Distant quiet contacts display silent overhead hand-sign emotes; audible calls
retain their real sound risk. Escalation can replace an obsolete low-count
warning without producing squad chatter. A bounded adapter also presents only
zombies already found by shared perception to the zombie's own spotted logic,
so zombies acquire companions normally without global zombie scans, local-
player registration, or stealing a materially closer player target.

0.22.8 makes actor actions, saves, lifecycle hooks, native cleanup and local
installation explicit transactions. Failed actions retain reservations and
rollback evidence; failed save validation preserves prior and quarantined raw
data; permanently incompatible restores stop retrying until manually released.
Native actors retain cleanup ownership until removal is verified, and bridge
startup validates every version-pinned reflected method before spawning.
Installer updates now restore config, JAR, manifest and payload at every tested
failure boundary. Configuration reload, scheduler diagnostics, faction limits,
provider IDs and dynamic perception caches are consistent and bounded. Public
source CI and trusted real-JAR release gates enforce these contracts.

0.22.7 adds player-like tactical combat readiness. Health, wounds, endurance,
panic, pain, tiredness, stress, morale, load, physical and weapon skills,
weapon weight/condition/sharpness, support, threat directions, footing and
escape quality now affect commitment and retreat. Companions preserve a real
stamina reserve, turn on rear and flank threats, spread across unclaimed
targets, and use shove/ground finishes only in a controlled lane. Safe firearm
shots require a settled sight picture; Aiming skill shortens it while panic and
stress lengthen it. Immediate defense and survival covering fire remain fast.

0.21.2 replaces repeated one-line speech with a shared intent-based dialogue
system. Recruitment, dismissal, danger warnings, needs, status, opinions,
relationships, encouragement, praise, personal plans, supply requests, work
failures, stress, joy, grief, infection crises, faction warnings and household
life now draw from bounded English line pools. Each speaker remembers recent
wording per topic and avoids it while alternatives remain. Personality and mood
can add voice-specific choices without changing an action's meaning, and named
context such as a dead companion is substituted safely. Dialogue history is
runtime-only and clears cleanly when the world closes. Actor-owned overhead
lines stay fully readable for a length-aware eight to fifteen real-time seconds
before the normal fade. Accelerated game time cannot erase a long line early,
repeated refreshes do not create duplicate rows, and a different new line still
replaces the old line.
Public metadata now declares ZombieBuddy 2.3.3 as a required dependency.

0.20.0 connects persistent households through a bounded faction-world graph.
Known groups exchange warnings, supplies and aid, develop disputes, and hear
proportionate word-of-mouth reports about important player actions. These
events never kill actors or damage bases off-screen. Camp operations now show
real classified-stock readiness, role coverage, watch rotation and persistent
workload/maintenance policies. Residents without an actionable job use safe
ambient downtime, and automatic work is queued only after a capable loaded
resident and the required real item have been found.

Project Zomboid belongs to The Indie Stone. This unofficial mod is not
affiliated with or endorsed by The Indie Stone.
