<!-- SPDX-License-Identifier: MIT -->

# The camp computer: EMMA

Every desktop computer in Knox Country still has EMMA on it: the Emergency
Management Assistant, an unfinished civil defense program the state installed
shortly before there was no state. She answers plain English at a full-screen
terminal. She is calm, precise and not especially kind about it.

EMMA makes no real internet connections and uses no hosted LLM or outside
service. She is a small offline parser with short-term context, and every
current-world fact she gives you comes from the save. References to county
networks and computer systems are fiction within the game.

## What is implemented

EMMA remains the Kentucky civil-defence beta installed on county machines in
1993, running on the fictional Larchfield Business Machines' LARCH/OS. Her
voice is bright, helpful and coldly matter-of-fact about a dead county. The
dialogue is original, with a dark edge inspired by GLaDOS rather than copied
lines. The operating system and the assistant are distinct.

- **Entirely offline.** No real internet requests, hosted LLM, external
  credentials or model downloads. Fictional county networks and computer
  services are allowed as part of the setting. Plain-English intents, synonyms,
  typo correction, names from game data and short-term context create the assistant effect.
  Answers use live save facts, concise lists and useful next steps. Unknown
  records get a clear explanation and suggestions for supported questions.
- **Presentation.** A centred, full-screen display uses large code text and an
  opaque background. Text scales with the viewport: 32-pixel font height at
  720p, 44 at 1080p and 88 at 4K, without changing the game's font settings.
  Narrow views switch between menu and chat rather than squeezing both in.
  Question-dependent thinking steps take roughly 0.5 to
  2.5 seconds, followed by streamed text. Power, returning-operator greetings,
  session counts and requested notes support continuity. Low cached generator
  fuel can affect presentation without inventing a power failure.
- **Local access.** Computer detection uses the native Computer property,
  supporting all facings and modded objects with the same tags. The right-click
  entry requires a powered, nearby computer. EMMA works on computers anywhere;
  camp records, including people and expeditions, require the computer inside
  camp. Portable state follows the game's furniture pickup/placement payload.
- **Security.** About 40% of newly discovered outside-camp computers are
  locked. A lock covers the whole machine and stays with it when moved.
  Already-used EMMA computers retain access. The word puzzle gives exact
  position matches; hidden bracket groups remove a wrong candidate or restore
  attempts. Electrical skill helps and a successful hack awards a small,
  one-time amount of Electrical XP. Failure imposes one game hour of lockout;
  the same puzzle returns with fresh attempts afterward. Reopening or
  reloading never rerolls a puzzle or restores a spent bracket.
- **Personal files.** Every computer has an assigned previous owner and
  short, original July 1993 entries matched to its room or building. Stories
  stay mostly grounded, with occasional dry humour. The owner and files remain
  fixed when the computer is revisited or moved.
- **System menu.** A numbered menu sits beside chat: camp report, the named
  owner's personal files, county and EMMA files, and log off. Both clicking and typing work. Ordinary
  text continues to EMMA, with history and context preserved.

The implementation stages are:

1. **Core and computer system:** persona, small talk, camp status, people,
   storage and jobs; LARCH/OS menus, password recovery, portable notes and
   personal files. Keep the existing headless phrasing table, typo/context
   checks and fixed-world answer tests, and add security and persistence tests.
2. **Confirmed actions and richer records:** checked medic/refuel requests
   through the same validated command paths as the existing menus, with an
   explicit Y/N confirmation and fresh validation when accepted. Expand wounds,
   skills, job suitability, shortages, alarms, radio reports, debriefs and
   pending-delivery answers. Never execute arbitrary text as code or commands.
3. **Lore and downtime:** 340 original entries across 85 owners, plus 16
   archived county and EMMA files. Companions can take a short break reading
   local files at an accessible camp computer.

World-data reads stay bounded and occur on a question or explicit command,
not every frame. UI animation runs through the existing window update; cheap
power/proximity checks protect an open session. Automated checks and completed
in-game scenarios are recorded separately.

The core, confirmed requests and expanded lore are implemented. The current alarm record covers the active
alarm and the last cleared alarm in this session; it is not a permanent log.
Companion computer use during downtime is included in 0.26.71.
Furniture movement, reload and hacking XP still need their
separate native acceptance pass.

## Branding coverage research

A read-only audit of the installed 42.21.0 stock map on 2026-10-26 found
3,536 placed desktop-computer sprites across 222 cells. It read 4,065 map
headers and the relevant lot packs, using the four desktop sprites identified
by the native tile definitions. Matching against room rectangles, including
buildings anchored in neighbouring cells, resolved 3,532 computers to 99 room
labels. Four placements at the map's northern edge had no matching room.
These are stock-map placements, not counts from a running save or random
furniture generation; they exclude challenge maps and modded maps.

The largest direct room label is `office` with 2,411 computers. Other useful
coverage includes 150 in police/detective offices, 240 in home room types,
132 in education room types, 82 in medical room types, and 57 in `laboratory`
or `lab`. Public `library` rooms add another 15 beyond the education total.
These groups describe rooms, not the distribution of named companies.

The game's `media/textures/printMedia/logos/` folder contains 184 PNG files.
Some are variants, duplicates or artwork fragments, so that is not a count
of distinct organisations. The catalogue retains the useful marks, redirects
duplicate names and replaces photos with their firm's emblem. Examples:

| Coverage | Existing original artwork |
| --- | --- |
| Research | `FinneganResearchGroup.png` |
| Health | `MedicalCentre.png`, `FamilyDentistry.png`, `OptimaEyes.png` |
| Education | `LouisvilleStateUniversity.png` |
| Broadcast and news | `LBMWNetwork.png`, `KnoxTalkRadio.png`, `ENewsNowNetwork.png`, `TheKentuckyHerald.png`, `AmeriglobeCommunications.png` |
| Banking and office services | `SkyBlueBanking.png`, `ValuInsurance.png`, `MindPeaceInsurance.png`, `HomewardRealEstate.png`, `SpeedyLegal.png` |
| Industrial and transport | `MassGenfacCo.png`, `UnitedShippingLogistics.png`, `KYTransit.png` |
| Electronics and retail | `Valutech.png`, `ElectronHouse.png`, `Spiffos.png`, `HitVids.png`, `WormOfBooks.png` |
| Fuel | `Fossoil.png` |
| Car sales | `nolanLogo.png`, `ScenicMileCarDealership.png` |
| Hotels and motels | `HavishamHotelSuites.png`, `EconoRoom.png`, `SleepEazzzeInn.png` |

The expanded catalogue provides 195 distinct terminal identities: 179 named
marks and 16 camp or sector emblems. New artwork includes Sunstar, U-Store It,
Lectromax, Pizza Whirled, Greene's, the Rusty Rifle, GigaMart and Jackie Jaye.
Food service, retail, hotels and electronics now have their own fallbacks.
McCoy, Knox Bank and several awkward sign-panel logos have transparent
terminal adaptations. GigaMart and Jackie Jaye are original terminal artwork
for verified room identities; they are not claimed as reproductions of stock
shop signs. Prompts and references are recorded in
`docs/terminal-art-manifest.json` and `docs/terminal-expanded-art-manifest.json`.

Brand selection follows these rules:

- Prefer a verified shop/unit or organisation match from a curated location
  or an unambiguous original sign associated with that unit. A room called
  `office`, a nearby sign across the street, or a brand elsewhere in the same
  mall is insufficient evidence. Mixed or unknown premises get a fallback.
- Use room type for the fallback and archive category. A lab is not
  automatically Finnegan, and a bank is not automatically Sky Blue.
- Keep the owner brand, the operating-system colour and EMMA's camp access
  separate. Preserve origin branding, files and lock state when furniture
  moves. A camp dashboard can display the camp emblem without changing the
  previous owner's identity.
- Inspect each original mark at thumbnail size. Preserve its aspect ratio;
  very long wordmarks and artwork with opaque backgrounds need special
  treatment. Keep each mark's recognisable colours, with common subdued CRT
  brightness, a gentle tube tint, scanlines and small phosphor corner marks.
  Fit without stretching and clip transparent source margins consistently.
  A scoped native UI shader removes suitable flat backing colours and makes
  dark ink readable. Purple uses matching monochrome phosphor. Source PNG
  pixels stay unchanged, and the shader releases its state after each draw.
- Resolve branding on first discovery or an explicit refresh, cache it and
  keep all sign/location searches bounded. Do not scan the world per frame.

Automatic assignment uses explicit branding, unambiguous native room labels,
40 curated native advert definitions and a bounded same-room sign search.
Conflicting tenants, generic offices and unknown businesses retain sector
emblems. A catalogue logo does not imply that every premises bearing that
name can be identified. No company is invented for an unknown building.

Owner stories cover more than two dozen contexts, including education,
research, news and broadcasting, retail, factories, transport, hospitality,
healthcare, farms and homes. Verified named firms prefer a matching archive;
newspaper brands use print-reporting stories rather than broadcast scripts.

Local research evidence is in `artifacts/emma/research/`:
`computer_logo_audit.py`, `computer-census.csv`,
`computer-census-summary.json` and `stock-logo-inventory.csv`. The parser was
checked against the installed JAR's `IsoMetaGrid` header loader, `IsoLot`
record reader and `IsoCell` tile lookup. The census itself did not launch a
game session; later native presentation checks are recorded separately.

## Using a computer

Stand near a desktop computer, right-click and choose **Use computer**. Your
character faces the screen and the terminal fills your player view. Its
content stays centred when the resolution changes. The computer needs power:
a generator in range, or grid power inside a building while the grid still
runs. The menu entry appears only for a powered, nearby computer.

The display sits inside an original 1993-style Larchfield monitor: beige ABS
plastic, side vents, a small power switch and green indicator at the left,
and brightness/contrast wheels at the right. Its straight lower bezel and
control layout were designed from scratch. A generated scanline-glass texture sits behind the live text, keeping
letters and the caret clear. The frame has a transparent screen opening and
scales in sections to preserve its corners and controls. The text stays large
and the content remains inside the glass at different resolutions. The two
skin assets are preloaded before first use.

The computer plays its startup recording once when it boots, using the
game's sound volume. The recording can finish over the welcome screen.
Skipping boot, closing the terminal or losing power stops it immediately.

- **Enter** skips the short animated memory and hardware checks during boot.
- Press a displayed **number** to select an item while the menu is focused,
  or use **Up/Down** and **Enter**. Clicking also works.
- **Tab** or **Shift+Tab** switches between menu and chat, keeping your draft.
  Start typing a question to enter chat; numbers in chat are ordinary text.
- Type a question and press **Enter**. EMMA thinks for a moment, then types.
- **Enter** while she is still typing skips to the end of her reply.
- In chat, **Up** and **Down** recall earlier lines. **Page Up**, **Page Down** and the
  mouse wheel scroll through the text. Long replies open at their question and
  first answer. Scrolling back keeps your place while EMMA types, and resizing
  preserves the text you are reading. The footer shows which rows are visible.
- Type `clear` to wipe the screen. **Esc** returns from a file submenu to
  EMMA; at the main menu it logs off. Typing `exit` also logs off.

The terminal closes if you walk away. If the power fails, the screen shows the
failure and goes dark.

Each machine receives green, golden-sand or aquamarine text matched to its
brand's colours. Fossoil uses aquamarine; warm marks favour golden sand and
green marks favour green. Neutral marks keep a seeded choice. About one in a
hundred receives purple as a special exception. Existing machines receive
their brand pairing once, then keep it when moved or reloaded. This does not
change locks, puzzles or notes. Logos retain their recognisable brand hues
with the same CRT treatment as the rest of the screen; rare purple screens
use a monochrome purple rendition. A computer at
home shows the camp emblem while retaining its previous owner's files.

## LARCH/OS, passwords and personal files

The numbered system menu sits beside EMMA. Select **Camp report**, open the
previous owner's **Personal files**, browse **County files and EMMA**, or
**Log off** by clicking or typing the
number while the menu is focused. Ordinary text still goes to EMMA. Escape returns from the file menu;
from the main menu it closes the terminal.

About 40% of newly discovered computers outside camp require a password.
Computers you have already used with EMMA retain access. A locked computer
stays locked when carried home; moving it does not change its owner or files.

Choose a six-letter word from the recovery screen. Feedback counts letters
in the correct positions. Hidden bracket groups can remove an incorrect
candidate or restore attempts. Both clicking and typing work. Higher
Electrical skill provides fewer candidates and more attempts. A successful
hack gives five base Electrical XP once for that computer.

Attempts, the latest feedback and any lockout timer stay above the scrolling
word board. It opens at the first candidates; **Page Up**, **Page Down** and
the wheel reach the remaining words, brackets and previous guesses.

Running out of attempts locks recovery for one game hour. Afterward, the same
words return with fresh attempts. Old feedback, removed candidates and used
bracket groups remain recorded. Closing, losing power or reloading does not
reroll the puzzle.

The file collection contains 340 original entries by 85 owners. Computers
receive a fixed owner appropriate to their room, building or verified firm.
These are dated July 1993 stories, separate from EMMA's current camp records.
The **County files and EMMA** menu adds 16 archived files about the assistant,
public notices, road reports, shelters and the county's last working days.
It works outside camp after unlocking the computer. Files are grouped into
small numbered pages; reading a long entry starts at its heading, and
Page Up/Page Down or the wheel scrolls through it. Existing computers keep
their original owner and files.

## What she can tell you

| Ask something like | She answers with |
| --- | --- |
| `status` | One camp report: people, work, food, power, weather and movement |
| `who is here`, `where is Kate` | Your recruited companions, what they are doing and where, by distance and compass direction from the terminal |
| `who is hurt`, `how is Kate` | Health, wounds and bandages, hunger, thirst, stress and spirits. Expedition members are reported as away |
| `who is best at first aid`, `skills` | Highest recorded relevant skills among the people currently at camp |
| `how many nails`, `any ammo left` | Counts across marked camp storage, with which containers hold them |
| `how much food` | Food items, total calories and roughly how many days they last for the people at camp |
| `what is everyone doing`, `any problems` | Work in progress, waiting and blocked, with blocked reasons |
| `power`, `weather`, `time` | Generator fuel and condition, outside temperature and sky, game date and day count |
| `any zombies` | Movement within 40 meters of the terminal, nearest distance and direction |
| `shortages`, `alarms` | Stock targets and incomplete audits; active camp alerts and the last cleared alert this session |
| `expedition`, `deliveries` | Observed or radio-reported progress, last debrief and returned cargo awaiting storage. Collected, carried and stored remain separate |
| `advice` | The most urgent thing she can see, in order: bleeding, low health, low generator fuel, a crowd outside, blocked work, low food, night |
| `remember the key is in the van` | Saves a note. `what did i tell you` reads notes back; `forget everything` erases them |

She tolerates typos, follows up on the last question (`and screws?`,
`is she hurt?`, `and now?`), and asks "Did you mean ...?" when she is unsure;
answer `yes` or `no`. She also does arithmetic, small talk, jokes and poems,
and has opinions about being insulted.

You can also ask EMMA to do a few practical things from a camp computer:

- `refuel generator` or `refuel <vehicle name>` queues the existing refuel job.
- `send medic to <name>` proposes an available companion with the highest
  First Aid skill who can currently reach and treat that person.
- `retry job <job ID>` retries one blocked job through the normal Retry path.
  EMMA includes the job ID and automatic retry countdown in blocked-work reports.

She names the target and asks `[Y/N]`. Type `y` or `yes`, then press Enter
to submit it; `n` or `no` cancels. Another question or menu selection cancels
the pending request too. Nothing happens before confirmation. Requests expire
after two real minutes and are discarded when the computer closes or loses
power. EMMA rechecks camp access, target identity and eligibility when you
accept. Treatment, supplies, safe routes and storage still follow the normal
game rules. An unlocatable cargo item is never counted as stored.

The camp emblem follows the computer's green, golden sand, aquamarine or
purple phosphor. Company marks use matching or complementary screen colours;
their shapes stay recognisable on all four backgrounds.

## Local building controls

Choose **Local services** from EMMA's numbered menu. A powered desktop can be
connected to its building with Electrical 2, a screwdriver, one electric wire
and two electronics scrap. An outdoor desktop can connect to a loaded building
within six tiles. Equipment discovery reads loaded squares in bounded slices;
use **Equipment** again while a large building is still being surveyed.

Building security has its own password, shared by that building's computers.
Unlocking the computer or moving an unlocked one into a bank does not authorize
the building. Recover the building password, or use its matching physical key.
No new locks are added to map doors. Another mod's coded or padlocked doors are
left to that mod.

- **Doors and shutters:** unlock/lock existing key locks. Remotely opening an
  ordinary door needs a fitted motor; camp shutters need one too. Native grouped
  garage doors move together. People, bodies, vehicles, barricades and lost
  actuator power block movement. The computer's backup battery cannot power a
  door motor.
- **Lights:** switch native lights, or a constructed floodlight with its own
  usable fuel/battery. Ordinary camp lights need a fitted relay. On an equipment
  page, type `name Kitchen lights` to rename a device, or `group Perimeter` to
  assign a light to a named group. Switching an unchanged state does no redraw.
- **Generators:** start, stop, repair or queue the existing camp refuel job. An
  available companion walks to the generator and uses the stock action. Missing
  scrap, blocked access and interrupted work use the existing camp retry
  policy. Outside camp, start/stop/repair use an idle nearby recruited companion
  who is following, staying or guarding. Local requests retry after three game
  minutes. A new order cancels that local request.
  A fitted remote starter uses a real removable car battery; each start attempt
  consumes one percent of its charge. Fuel, connection, condition and native
  startup failures still apply.
- **Security:** arm/disarm the existing building alarm, silence this building's
  active alarm, or fit a speaker for a siren and evacuation announcement. Both
  speaker modes make real noise that attracts infected. Silence does not stop
  alarms in other buildings. Contacts, motion detections and supply changes are
  recorded in a history limited to 256 entries.

Relay/contact installation needs Electrical 3, a screwdriver, one wire and two
scrap. A motor needs Electrical 4, one wire and four scrap. Motion sensing adds
one actual motion sensor and needs Electrical 4. A siren/PA needs Electrical 3,
an amplifier, one wire and two scrap. A remote starter needs Electrical 4,
two wires, four scrap and a real car battery. Installation is a cancellable
physical action beside the selected device; components are checked at completion.

**Automatic routines are opt-in.** Night lighting switches the selected lights
at 20:00 and 06:00. Lockdown closes and locks the authorized openings, leaving
obstructed steps pending. Select a real loading shutter as the return garage
before enabling its return routine. It opens for an approaching expedition and
closes only after the crew is home, the returned car is stopped inside with its
engine off, and the doorway is clear. Roadside parking leaves closure pending.
Moving/disconnecting the authorizing computer suspends its routines.

## Upgrade to an expedition station

Mount a real two-way walkie-talkie with Electrical 2, a screwdriver, one wire
and two scrap. The computer gains an antenna on its frame. Its native radio
keeps its identity, tuning and original battery; the PC powers the mounted
receiver without charging that original battery. Type `channel 88100` to tune
it, or use **Radio channel / status**. Expedition radios must be equipped,
working, tuned to the same channel and within their native transmission ranges.
A progress report requires an actual return transmission; unreachable crew do
not reveal fresh remote information.

From a camp station you can review and launch walking or driving wood, search,
scouting and fishing expeditions, select the crew/leader, request progress,
recall them and answer route-block decisions. Wood supports **Full load**, with
the existing 256-log ceiling. Reviewed crew and mission details are rechecked
before launch. The station can also book, inspect or cancel Marcus's taxi
through the same booking service as a handheld radio.

An optional UPS needs Electrical 4, a screwdriver, one wire, four scrap and a
charged car battery. A full healthy battery supplies six game hours of active
PC/radio use; poor condition shortens that time. It supplies this computer only
and never changes the building's electricity. Remove it to recharge normally.
Radios, UPS batteries, locks, files and memory move with the native furniture
item. Their added weight counts. A native pickup break drops the exact mounted
parts; an uncertain native transfer is recorded for inspection and never replayed.
You can remove upgrades beside an unpowered PC through its context menu.

Connected services and radio receivers use the existing one-second scheduler.
Nearby computer discovery reads at most 256 loaded squares per slice; sensors
share a separate 256-check budget and never load distant map cells.

**LF circuits need no other mod.** Named lighting circuits operate the fitted
native relays; the generator-supply circuit queues the normal start/stop services.
Grid supply stays independent. Individual fridge/freezer isolation requires a
further native extension: this version does not simulate it by changing food
or inventory containers. Stopping the actual generator still removes its real
refrigeration supply normally.

## Companions at the computer

With safe routines enabled, a companion may use a powered, unlocked computer
in the same camp room during a quiet break. One person uses a machine at a
time. They walk to a genuine access position and spend about 18 seconds
reading local county or EMMA files. Illiterate companions choose another
activity. A successful visit records which file they read and has a ten-minute
cooldown; blocked access pauses attempts for two minutes.

Opening the computer takes priority over a companion's visit. Danger, a new
order, loss of power, removal of the machine or disabling routines also stops
it. Companions use the existing native hand-work pose rather than opening a
second terminal window. They do not unlock machines, submit requests, earn
hacking XP, change inventories or read and rewrite the player's private notes.

## Rules

- **Camp records stay at home.** Questions about people, storage, food, jobs
  and expeditions need the computer inside your marked camp. Outside it,
  EMMA still answers about local power, weather, time and movement, keeps
  your notes and offers small talk. Carry a computer home for camp access.
- **Bounded reads.** Every answer reads the world once, when you ask. Storage
  counting stops at 40 containers, 600 items each and 4,000 in total, and
  EMMA says when a count may be incomplete (for example, an unloaded
  container). The zombie count scans at most 2,000 entries.
- **Memory.** Each computer keeps its own small memory in the save: the name
  you gave with `call me ...`, up to eight notes of 80 characters, and when
  you last visited. Damaged or oversized memory is cleaned up or ignored on
  read.
- **Single-player keyboard player only**, like the rest of the mod.

## Verification

With a marked camp, a generator and a desktop computer:

1. Right-click a computer without a UPS with the generator off. **Use computer**
   should be absent. Turn the generator on, stand nearby and use it. The character
   faces the screen and the boot screen types out.
2. Ask `how many nails`, then `and screws?`, then `how many of them`. Compare
   the counts with the shelves.
3. Ask `who is hurt` and `how is <name>` for a companion. Wound a companion
   and ask again.
4. Ask `status`, `power`, `weather`, `time` and `any zombies`. Check the
   generator fuel against its own panel.
5. Type `call me <name>` and `remember <something>`, leave with `exit`, save
   and reload, and use the same computer. EMMA should greet you by name, say
   how long you were gone and read the note back with `what did i tell you`.
6. Use an unlocked computer outside camp. People, storage and expedition
   questions should explain the missing camp access; time and weather work.
7. Walk away mid-reply, and separately turn the generator off while the
   terminal is open. The first closes at once; the second shows
   `*** POWER FAILURE ***` before closing.

The `terminal` gameplay harness covers the intents, typo tolerance, context,
every answer against fixtures, memory normalization, fuzzed input and the live
world adapter against fake game objects. The UI tests cover the menu entry,
the walk-and-sit action, the boot screen, typing, history, clear, exit,
walking away, power loss and memory across sessions.

Also verify a word guess and bracket bonus, close and reopen to check the
board persists, exhaust the attempts and wait one game hour. Confirm the same
board returns and XP is awarded once when unlocked. Move a used computer
through furniture pickup and placement; its lock or unlock, owner files,
remembered name and notes should stay with it.
