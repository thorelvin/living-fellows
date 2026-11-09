<!-- SPDX-License-Identifier: MIT -->

# Living Fellows

*You won't die... alone.*

**[Read the Field Guide →](https://thorelvin.github.io/living-fellows/)** · [Quick reference](https://thorelvin.github.io/living-fellows/quick-reference.html) · [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3805760339)

<p align="center">
  <img src="assets/banner.png" width="100%" alt="Living Fellows: survivors walking a dusk street together">
</p>

[![Release](https://img.shields.io/badge/release-0.27.5-blue.svg)](CHANGELOG.md)
[![Project Zomboid](https://img.shields.io/badge/Project%20Zomboid-42.22.2-red.svg)](#requirements)
[![Single-player](https://img.shields.io/badge/mode-single--player-orange.svg)](#requirements)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Find your people. Give them a place to live. Try to bring everyone home.

Living Fellows adds companions, survivor households and working bases to Project Zomboid. Your fellows carry real supplies, get hurt, remember what happens to them and make their own decisions when things go wrong.

## More than someone following you

- **Send a squad on an expedition.** Scout a building, search for supplies, fish or collect wood while you get on with your own plans. Send one to four companions on foot or by car, choose a target on your map, a leader and return time, and watch their trip in a second view. They bring back what they actually find and carry it into camp storage.
- **Keep the camp working with Base Watch.** Leave an indoor resident on watch and the camp stays loaded while you travel. The others keep sorting, farming, cooking, repairing and guarding. Check in by radio while you're away. Base Watch and expeditions share one companion view, so run one at a time.
- **Call Markus's taxi.** Stranded on the road? Call for pickup from a working walkie-talkie, climb into Markus Sloane's cab and choose a road destination on the map. Bring jewelry for the fare.
- **Build a crew worth knowing.** Up to 16 companions with professions, personalities, relationships and memories. They fight in formation, look after their needs, treat wounds and retreat when they're outmatched. Some keep private diaries. Death is permanent, and the book stays behind.
- **Make a home that works.** Mark storage and work areas, assign jobs, grow food, build, fell trees, saw planks and bury the dead. Wood goes into neat four-log stacks. Blocked jobs pause and retry automatically; manual Retry stays available.
- **Ask EMMA.** Check camp supplies, people and jobs, recover locked computers, or reconnect substations to restore grid power. EMMA remembers notes, handles follow-ups and confirms actions with you. Ask for practical survival advice, or browse 568 entries left by previous owners and 151 county and EMMA files. Everything runs offline on a full-screen 1993 terminal. [More](docs/camp-computer.md).
- **Meet the people still out there.** Households trade, offer work and remember how you treat them. Strange Folk bring their own stories, requests and bad habits. Encounters can begin on the second day, with a random eligible character each time.

The [Field Guide](https://thorelvin.github.io/living-fellows/) covers orders, camp jobs, equipment, travel and the people you'll meet.

## Requirements

**Project Zomboid Build 42.22.2 · Single-player.** Multiplayer and additional human split-screen players are not supported.

Choose one installation method. Workshop and standalone copies share the same mod ID and should not be enabled together.

Using Bandits2 too? See the [optional adapter's scope and test results](docs/compatibility-bandits2.md).
There is also optional [Project A-Life compatibility](docs/compatibility-project-alife.md). Use one external NPC mod at a time.

### Steam Workshop

1. Subscribe to [ZombieBuddy](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853) **2.3.3 or newer** and complete its one-time loader setup. Subscribing alone is not enough.
2. Subscribe to [Living Fellows](https://steamcommunity.com/sharedfiles/filedetails/?id=3805760339).
3. Start the game and enable both in **Mods**. For an existing save, enable both under **More… → Choose Mods** too.

### Standalone for Windows

1. Download the complete repository with **Code → Download ZIP**, or get the standalone Windows package from [Releases](https://github.com/thorelvin/living-fellows/releases).
2. Extract the whole folder, close Project Zomboid and run **Install.bat**.
3. Start the game and enable **Living Fellows** in **Mods** and in the save's **More… → Choose Mods** menu.

This edition includes its own bridge and does not need ZombieBuddy. Keep the extracted folder: **Uninstall.bat** removes the installation. See [INSTALL.md](INSTALL.md) for another Steam library, updating or troubleshooting.

## Your first few minutes

1. Press **Home** to open the companion panel, or click the small **LF** launcher.
2. Meet a survivor, right-click them and choose **Talk to (name) → Invite to join**. Use **Talk** to get to know them.
3. Set orders and combat style in **Orders**; put companions into groups in **Squad**.
4. Right-click the ground and choose **Living Fellows → Set camp core here**. Mark storage, then assign jobs at the top of **More → Base**. To remove a storage marking, right-click its container and choose **Living Fellows → Unmark storage**.

To mark an area, choose its type at the first corner, then **left-click the opposite corner** to finish. Right-click or press **Esc** to cancel.

The **First steps** card on Status follows your progress, with a short reminder beside the collapsed launcher. New worlds get an early independent survivor who approaches cautiously; the first arrival gets a one-time clearing of hidden, idle zombies nearby. They remain vulnerable. Dismiss the card or turn **Show tips** off in Mod Options; **Show tips again** brings it back. **More → Support → Tips** keeps the instructions you've seen.

The orange **LF** tab shows a badge when something needs attention. **Review** opens the relevant decision or blocked job; **Acknowledge** hides its notice while keeping the badge. Status explains **Why paused** and how to recover. Infection decisions use the evidence your character knows: watch allows indoor duties, unavailable quarantine stays pending, and irreversible outcomes require your confirmation.

On a powered camp computer with a mounted walkie-talkie, open **Local services → LARCH/WAVE radio desk → Survivor radio watch**. Assign a companion on base duty and monitor their signal search. A four-hour shift has a 35% chance to find a survivor; you decide whether to invite them. Needs, danger and power loss pause the work without losing progress.

Hold **keypad 1** to Peek, press **keypad 2** to toggle Watch, or hold **keypad 3** to steer the selected companion toward the cursor. All three keys can be rebound. Companions, households and camp work are saved with the world, even if your character dies.

## Need a hand?

Open **More → Support** for a diagnostic report. If the panel is missing, check that the mod is enabled for the save; Workshop users should also check ZombieBuddy's loader setup. A stuck companion may recover with **Regroup**.

For a [bug report](https://github.com/thorelvin/living-fellows/issues/new/choose), include the Support report, game and mod versions, what happened and a screenshot or relevant logs. Remove private information before posting.

[What's new](CHANGELOG.md) · [Contributing and building](CONTRIBUTING.md) · [Architecture](ARCHITECTURE.md)

Original mod, [MIT licensed](LICENSE). Project Zomboid belongs to The Indie Stone; Living Fellows is not affiliated with or endorsed by them.
